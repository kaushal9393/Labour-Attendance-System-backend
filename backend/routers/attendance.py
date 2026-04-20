import logging
from datetime import datetime, date, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from core.database import get_db
from core.security import get_current_user
from core.face_service import check_liveness, get_embedding
from models.schemas import (
    ScanRequest, ScanResponse,
    TodayAttendanceResponse, AttendanceRecord,
    MonthlyAttendanceRecord,
)

logger = logging.getLogger("garage_api.attendance")
router = APIRouter(prefix="/api/attendance", tags=["Attendance"])

# InsightFace ArcFace standard: same-person cosine similarity ~0.4–0.7,
# different-person ~0.0–0.3. 0.45 is the industry-recommended cutoff.
COSINE_THRESHOLD = 0.45


# ─── POST /api/attendance/scan ────────────────────────────────
# No JWT required — kiosk devices are not logged in
@router.post("/scan", response_model=ScanResponse)
async def scan_face(
    payload: ScanRequest,
    db:      AsyncSession = Depends(get_db),
):
    # Resolve company_id from company_code
    company_row = await db.execute(
        text("SELECT id FROM companies WHERE company_code = :code"),
        {"code": payload.company_code},
    )
    company = company_row.fetchone()
    if not company:
        raise HTTPException(status_code=404, detail="Invalid company code")
    company_id = company[0]

    # 1. Liveness check
    is_live, reason = check_liveness(payload.image)
    if not is_live:
        return ScanResponse(success=False, reason=f"liveness_failed:{reason}")

    # 2. Generate embedding
    embedding = get_embedding(payload.image)
    if embedding is None:
        return ScanResponse(success=False, reason="face_embedding_failed")

    # 3. Direct pgvector query — get top match across all 3 angles
    #    cosine distance  = fv.face_vector <=> query_vec    (range 0..2)
    #    cosine similarity = 1 - cosine_distance            (range -1..1)
    vec_str = "[" + ",".join(str(x) for x in embedding) + "]"
    row = await db.execute(
        text(
            "SELECT e.id, e.name, fv.angle_type, "
            "1 - (fv.face_vector <=> CAST(:vec AS vector)) AS similarity "
            "FROM face_vectors fv "
            "JOIN employees e ON e.id = fv.employee_id "
            "WHERE e.company_id = :cid AND e.status != 'deleted' "
            "ORDER BY fv.face_vector <=> CAST(:vec AS vector) ASC "
            "LIMIT 1"
        ),
        {"vec": vec_str, "cid": company_id},
    )
    match = row.fetchone()

    if not match:
        logger.info(f"[Scan] No face_vectors for company_id={company_id}")
        return ScanResponse(success=False, reason="face_not_recognized")

    emp_id, emp_name, angle_type, similarity = match
    similarity = float(similarity)
    logger.info(
        f"[Scan] Top match: {emp_name} (id={emp_id}, angle={angle_type}) "
        f"similarity={similarity:.4f} threshold={COSINE_THRESHOLD}"
    )

    if similarity < COSINE_THRESHOLD:
        return ScanResponse(
            success=False,
            reason=f"face_not_recognized (top={similarity:.2f} < {COSINE_THRESHOLD})",
        )
    now        = datetime.now(timezone.utc).replace(tzinfo=None)
    today      = now.date()
    time_str   = now.strftime("%H:%M:%S")

    # 4. Get company settings for late threshold
    settings_row = await db.execute(
        text("SELECT work_start_time, late_threshold_minutes FROM settings WHERE company_id = :cid"),
        {"cid": company_id},
    )
    settings = settings_row.fetchone()
    work_start = settings[0] if settings else None
    late_mins  = settings[1] if settings else 15

    # 5. Check existing attendance record for today
    existing = await db.execute(
        text(
            "SELECT id, check_in, check_out FROM attendance "
            "WHERE employee_id = :eid AND attendance_date = :today"
        ),
        {"eid": emp_id, "today": today},
    )
    record = existing.fetchone()

    if record is None:
        # ── First scan of the day → check_in
        status = _determine_status(now, work_start, late_mins)
        await db.execute(
            text(
                "INSERT INTO attendance (employee_id, company_id, attendance_date, check_in, status, match_score) "
                "VALUES (:eid, :cid, :today, :now, :status, :score)"
            ),
            {"eid": emp_id, "cid": company_id, "today": today,
             "now": now, "status": status, "score": round(similarity, 4)},
        )
        action = "check_in"
    elif record[2] is None:
        # ── Second scan → check_out
        await db.execute(
            text("UPDATE attendance SET check_out = :now WHERE id = :rid"),
            {"now": now, "rid": record[0]},
        )
        action = "check_out"
    else:
        # Already checked out — update check_out to latest
        await db.execute(
            text("UPDATE attendance SET check_out = :now WHERE id = :rid"),
            {"now": now, "rid": record[0]},
        )
        action = "check_out"

    await db.commit()
    return ScanResponse(
        success=True,
        employee_name=emp_name,
        time=time_str,
        action=action,
        match_score=round(similarity, 4),
    )


# ─── GET /api/attendance/today ────────────────────────────────
@router.get("/today", response_model=TodayAttendanceResponse)
async def today_attendance(
    db:   AsyncSession = Depends(get_db),
    user: dict         = Depends(get_current_user),
):
    company_id = user["company_id"]
    today = date.today()

    rows = await db.execute(
        text(
            "SELECT a.id, a.employee_id, e.name, e.profile_photo_url, "
            "a.attendance_date, a.check_in, a.check_out, a.status, a.match_score "
            "FROM attendance a "
            "JOIN employees e ON e.id = a.employee_id "
            "WHERE a.company_id = :cid AND a.attendance_date = :today "
            "ORDER BY a.check_in ASC NULLS LAST"
        ),
        {"cid": company_id, "today": today},
    )
    records_raw = rows.fetchall()

    records = [
        AttendanceRecord(
            id=r[0], employee_id=r[1], employee_name=r[2],
            profile_photo_url=r[3], attendance_date=r[4],
            check_in=r[5], check_out=r[6], status=r[7], match_score=r[8],
        )
        for r in records_raw
    ]

    present = sum(1 for r in records if r.status in ("present", "late"))
    late    = sum(1 for r in records if r.status == "late")
    absent  = sum(1 for r in records if r.status == "absent")

    return TodayAttendanceResponse(
        date=today,
        total_present=present,
        total_absent=absent,
        total_late=late,
        records=records,
    )


# ─── GET /api/attendance/monthly ─────────────────────────────
@router.get("/monthly", response_model=List[MonthlyAttendanceRecord])
async def monthly_attendance(
    month:       int = Query(..., ge=1, le=12),
    year:        int = Query(..., ge=2020),
    employee_id: int = Query(...),
    db:   AsyncSession = Depends(get_db),
    user: dict         = Depends(get_current_user),
):
    company_id = user["company_id"]

    rows = await db.execute(
        text(
            "SELECT a.attendance_date, a.check_in, a.check_out, a.status, a.match_score "
            "FROM attendance a "
            "JOIN employees e ON e.id = a.employee_id "
            "WHERE a.employee_id = :eid AND a.company_id = :cid "
            "AND EXTRACT(MONTH FROM a.attendance_date) = :month "
            "AND EXTRACT(YEAR  FROM a.attendance_date) = :year "
            "ORDER BY a.attendance_date"
        ),
        {"eid": employee_id, "cid": company_id, "month": month, "year": year},
    )
    return [
        MonthlyAttendanceRecord(
            attendance_date=r[0], check_in=r[1],
            check_out=r[2], status=r[3], match_score=r[4],
        )
        for r in rows.fetchall()
    ]


# ─── Helpers ──────────────────────────────────────────────────
def _determine_status(now: datetime, work_start, late_mins: int) -> str:
    if work_start is None:
        return "present"
    from datetime import timedelta
    cutoff = datetime.combine(now.date(), work_start) + timedelta(minutes=late_mins)
    return "late" if now > cutoff else "present"
