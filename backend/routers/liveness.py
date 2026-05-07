"""
liveness.py — AWS Face Liveness endpoints.

Flow:
1. Client calls POST /api/liveness/session  -> backend creates AWS session, returns SessionId
2. Client (WebView) runs Amplify Liveness UI which performs the check against AWS directly
3. Client calls POST /api/liveness/verify with SessionId + company_code
   -> backend fetches results, validates confidence, runs face match, marks attendance
"""
import logging
import json as _json
from datetime import datetime, timedelta, timezone, date

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from sqlalchemy import text

from core.database import AsyncSessionLocal
from core.cache import cache
from core.aws_rekognition_service import (
    create_liveness_session,
    get_liveness_result,
    find_similar,
)

logger = logging.getLogger("garage_api.liveness")
router = APIRouter(prefix="/api/liveness", tags=["Liveness"])

import os

# Minimum AWS liveness confidence (0-100). Spoofing attempts typically score
# below 50; real users on mobile cameras land in the 70-95 range depending on
# lighting. Default 70 keeps spoof rejection while accepting real users; tune
# via LIVENESS_MIN_CONFIDENCE env var if needed.
LIVENESS_MIN_CONFIDENCE = float(os.getenv("LIVENESS_MIN_CONFIDENCE", "70"))


class CreateSessionResponse(BaseModel):
    session_id: str


class VerifyRequest(BaseModel):
    session_id: str
    company_code: str


class VerifyResponse(BaseModel):
    success: bool
    reason: str | None = None
    employee_name: str | None = None
    time: str | None = None
    action: str | None = None
    match_score: float | None = None
    liveness_confidence: float | None = None


@router.post("/session", response_model=CreateSessionResponse)
async def create_session():
    """Create an AWS Face Liveness session — frontend uses this SessionId."""
    try:
        sid = create_liveness_session()
    except Exception as e:
        logger.error(f"[Liveness] CreateSession failed: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to create liveness session: {e}")
    return CreateSessionResponse(session_id=sid)


@router.post("/verify", response_model=VerifyResponse)
async def verify_and_scan(payload: VerifyRequest):
    """
    Pull liveness results from AWS, then run face match + mark attendance.
    Replaces the old /api/attendance/scan flow when liveness is enabled.
    """
    # 1. Fetch liveness result
    try:
        result = get_liveness_result(payload.session_id)
    except Exception as e:
        logger.error(f"[Liveness] GetResult failed: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to fetch liveness result: {e}")

    status = result["status"]
    confidence = result["confidence"]
    ref_bytes = result["reference_image_bytes"]

    if status != "SUCCEEDED":
        return VerifyResponse(success=False, reason="liveness_failed",
                              liveness_confidence=confidence)

    if confidence < LIVENESS_MIN_CONFIDENCE:
        return VerifyResponse(success=False, reason="liveness_low_confidence",
                              liveness_confidence=confidence)

    if not ref_bytes:
        return VerifyResponse(success=False, reason="no_reference_image",
                              liveness_confidence=confidence)

    # 2. Resolve company_id
    async with AsyncSessionLocal() as db:
        cache_key = f"company_code_{payload.company_code}"
        company_id = cache.get(cache_key)
        if company_id is None:
            row = await db.execute(
                text("SELECT id FROM companies WHERE company_code = :code"),
                {"code": payload.company_code},
            )
            company = row.fetchone()
            if not company:
                raise HTTPException(status_code=404, detail="Invalid company code")
            company_id = company[0]
            cache.set(cache_key, company_id, ttl_seconds=3600)

        # 3. Match face against company collection (using AWS reference image bytes)
        match = find_similar(company_id, ref_bytes)
        if match is None:
            return VerifyResponse(success=False, reason="face_not_recognized",
                                  liveness_confidence=confidence)

        face_id, similarity = match

        # 4. Lookup employee
        emp_rows = await db.execute(
            text(
                "SELECT id, name, azure_person_id FROM employees "
                "WHERE company_id = :cid AND status != 'deleted'"
            ),
            {"cid": company_id},
        )
        emp_id, emp_name = None, None
        for row in emp_rows.fetchall():
            try:
                face_ids = _json.loads(row[2]) if row[2] else []
                if face_id in face_ids:
                    emp_id, emp_name = row[0], row[1]
                    break
            except Exception:
                continue

        if emp_id is None:
            return VerifyResponse(success=False, reason="face_not_recognized",
                                  liveness_confidence=confidence)

        logger.info(f"[Liveness] Match: {emp_name} liveness={confidence:.1f} sim={similarity:.4f}")

        # 5. Attendance logic (mirror of /api/attendance/scan)
        _IST = timezone(timedelta(hours=5, minutes=30))
        now = datetime.now(tz=_IST).replace(tzinfo=None)
        today = now.date()
        time_str = now.strftime("%H:%M:%S")

        settings_row = await db.execute(
            text(
                "SELECT work_start_time, late_threshold_minutes, "
                "checkin_window_start, checkin_window_end "
                "FROM settings WHERE company_id = :cid"
            ),
            {"cid": company_id},
        )
        settings = settings_row.fetchone()
        work_start = _to_time(settings[0]) if settings else None
        late_mins  = settings[1] if settings else 15
        ci_start   = _to_time(settings[2]) if settings else None
        ci_end     = _to_time(settings[3]) if settings else None

        existing = await db.execute(
            text("SELECT id, check_in, check_out FROM attendance "
                 "WHERE employee_id = :eid AND attendance_date = :today"),
            {"eid": emp_id, "today": today},
        )
        record = existing.fetchone()
        now_time = now.time().replace(microsecond=0)

        if record is None:
            outside_ci = False
            if ci_start is not None and ci_end is not None:
                try:
                    outside_ci = not (ci_start <= now_time <= ci_end)
                except TypeError:
                    outside_ci = False
            att_status = "late" if outside_ci else _determine_status(now, work_start, late_mins)
            await db.execute(
                text(
                    "INSERT INTO attendance (employee_id, company_id, attendance_date, "
                    "check_in, status, match_score) "
                    "VALUES (:eid, :cid, :today, :now, :status, :score) "
                    "ON CONFLICT (employee_id, attendance_date) DO NOTHING"
                ),
                {"eid": emp_id, "cid": company_id, "today": today,
                 "now": now, "status": att_status, "score": round(similarity, 4)},
            )
            action = "check_in"
        else:
            await db.execute(
                text("UPDATE attendance SET check_out = :now WHERE id = :rid"),
                {"now": now, "rid": record[0]},
            )
            action = "check_out"

        await db.commit()
        cache.invalidate(f"today_attendance_{company_id}_{today}")

        return VerifyResponse(
            success=True,
            employee_name=emp_name,
            time=time_str,
            action=action,
            match_score=round(similarity, 4),
            liveness_confidence=confidence,
        )


# Helpers (same as attendance.py — duplicated to avoid cross-router imports)
from datetime import time as dt_time

def _to_time(v):
    if v is None:
        return None
    if isinstance(v, dt_time):
        return v
    if isinstance(v, timedelta):
        total = int(v.total_seconds())
        return dt_time(total // 3600, (total % 3600) // 60, total % 60)
    try:
        parts = str(v).split(":")
        return dt_time(int(parts[0]), int(parts[1]), int(float(parts[2])))
    except Exception:
        return None


def _determine_status(now: datetime, work_start, late_mins: int) -> str:
    if work_start is None:
        return "present"
    cutoff = datetime.combine(now.date(), work_start) + timedelta(minutes=late_mins)
    return "late" if now > cutoff else "present"
