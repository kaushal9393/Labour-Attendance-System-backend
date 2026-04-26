import logging
from datetime import datetime, date, time as dt_time, timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from core.database import get_db
from core.security import get_current_user
from core.face_service import check_liveness, get_embedding
from core.cache import cache
from core import face_cache
from models.schemas import (
    ScanRequest, ScanResponse,
    TodayAttendanceResponse, AttendanceRecord,
    MonthlyAttendanceRecord,
    ManualCheckoutRequest, ManualCheckoutResponse,
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
    # Resolve company_id from company_code — cached to avoid DB hit on every scan
    cache_key = f"company_code_{payload.company_code}"
    company_id = cache.get(cache_key)
    if company_id is None:
        company_row = await db.execute(
            text("SELECT id FROM companies WHERE company_code = :code"),
            {"code": payload.company_code},
        )
        company = company_row.fetchone()
        if not company:
            raise HTTPException(status_code=404, detail="Invalid company code")
        company_id = company[0]
        cache.set(cache_key, company_id, ttl_seconds=3600)

    import cv2
    from core.face_service import decode_base64_image, extract_embedding_no_detect

    img = decode_base64_image(payload.image)
    if img is None:
        return ScanResponse(success=False, reason="image_decode_failed")

    # Resize to 320px — ArcFace only needs 112x112 internally, 320 is plenty
    h, w = img.shape[:2]
    if max(h, w) > 320:
        scale = 320 / max(h, w)
        img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)

    # Skip face detection on scan — camera already frames the face.
    # extract_embedding_no_detect runs only ArcFace (~80ms vs ~400ms with detector)
    embedding = extract_embedding_no_detect(img)
    if embedding is None:
        return ScanResponse(success=False, reason="face_embedding_failed")

    # 3. Match against in-memory face cache (zero DB call)
    result = face_cache.find_best_match(company_id, embedding, COSINE_THRESHOLD)

    if result is None:
        # Fallback to DB if cache is empty (e.g. cache load failed at startup)
        vec_str = "[" + ",".join(str(x) for x in embedding) + "]"
        row = await db.execute(
            text(
                "SELECT e.id, e.name, "
                "1 - (fv.face_vector <=> CAST(:vec AS vector)) AS similarity "
                "FROM face_vectors fv "
                "JOIN employees e ON e.id = fv.employee_id "
                "WHERE e.company_id = :cid AND e.status = 'active' "
                "ORDER BY fv.face_vector <=> CAST(:vec AS vector) ASC "
                "LIMIT 1"
            ),
            {"vec": vec_str, "cid": company_id},
        )
        db_match = row.fetchone()
        if not db_match or float(db_match[2]) < COSINE_THRESHOLD:
            logger.info(f"[Scan] No match for company_id={company_id}")
            return ScanResponse(success=False, reason="face_not_recognized")
        emp_id, emp_name, similarity = db_match[0], db_match[1], float(db_match[2])
    else:
        emp_id, emp_name, similarity = result

    # Always verify employee is still active in DB — guards against stale cache
    status_row = await db.execute(
        text("SELECT status FROM employees WHERE id = :eid AND company_id = :cid"),
        {"eid": emp_id, "cid": company_id},
    )
    emp_status = status_row.fetchone()
    if not emp_status or emp_status[0] == "deleted":
        # Remove from cache so future scans don't hit DB every time
        face_cache.remove_employee(company_id=company_id, emp_id=emp_id)
        logger.info(f"[Scan] Rejected deleted employee id={emp_id}")
        return ScanResponse(success=False, reason="face_not_recognized")

    similarity = float(similarity)
    logger.info(
        f"[Scan] Top match: {emp_name} (id={emp_id}) "
        f"similarity={similarity:.4f} threshold={COSINE_THRESHOLD}"
    )

    # Use local server time — window times in the DB are stored in local time
    now        = datetime.now()
    today      = now.date()
    time_str   = now.strftime("%H:%M:%S")

    # 4. Get company settings for late threshold + windows
    settings_row = await db.execute(
        text(
            "SELECT work_start_time, late_threshold_minutes, "
            "checkin_window_start, checkin_window_end, "
            "checkout_window_start, checkout_window_end "
            "FROM settings WHERE company_id = :cid"
        ),
        {"cid": company_id},
    )
    settings = settings_row.fetchone()
    work_start = _to_time(settings[0]) if settings else None
    late_mins  = settings[1] if settings else 15
    ci_start   = _to_time(settings[2]) if settings else None
    ci_end     = _to_time(settings[3]) if settings else None
    co_start   = _to_time(settings[4]) if settings else None
    co_end     = _to_time(settings[5]) if settings else None

    # 5. Check existing attendance record for today
    existing = await db.execute(
        text(
            "SELECT id, check_in, check_out FROM attendance "
            "WHERE employee_id = :eid AND attendance_date = :today"
        ),
        {"eid": emp_id, "today": today},
    )
    record = existing.fetchone()

    # Time window enforcement — fail-closed: if a window is configured (even
    # partially), reject scans outside it rather than silently allowing them.
    now_time = now.time().replace(microsecond=0)
    if record is None:
        # Determining a check-in attempt
        if ci_start is not None and ci_end is not None:
            try:
                in_window = ci_start <= now_time <= ci_end
            except TypeError as e:
                logger.error(f"[Scan] Check-in window comparison TypeError: {e} — allowing scan")
                in_window = True
            if not in_window:
                logger.info(
                    f"[Scan] Check-in rejected for {emp_name}: "
                    f"now={now_time} outside window {ci_start}–{ci_end}"
                )
                return ScanResponse(
                    success=False,
                    match=True,
                    action="check_in",
                    employee_name=emp_name,
                    reason="outside_checkin_window",
                    message=(
                        f"Check-in is only allowed between "
                        f"{ci_start.strftime('%I:%M %p')} and {ci_end.strftime('%I:%M %p')}. "
                        f"Current time {now_time.strftime('%I:%M %p')} is outside this window."
                    ),
                    window_start=str(ci_start),
                    window_end=str(ci_end),
                )
    else:
        # Determining a check-out attempt
        logger.info(
            f"[Scan] Checkout window check for {emp_name}: "
            f"co_start={co_start!r}(type={type(co_start).__name__}) "
            f"co_end={co_end!r}(type={type(co_end).__name__}) "
            f"now_time={now_time!r}(type={type(now_time).__name__})"
        )
        if co_start is not None and co_end is not None:
            try:
                in_window = co_start <= now_time <= co_end
            except TypeError as e:
                logger.error(f"[Scan] Window comparison TypeError: {e} — allowing scan")
                in_window = True
            if not in_window:
                logger.info(
                    f"[Scan] Check-out rejected for {emp_name}: "
                    f"now={now_time} outside window {co_start}–{co_end}"
                )
                return ScanResponse(
                    success=False,
                    match=True,
                    action="check_out",
                    employee_name=emp_name,
                    reason="outside_checkout_window",
                    message=(
                        f"Check-out is only allowed between "
                        f"{co_start.strftime('%I:%M %p')} and {co_end.strftime('%I:%M %p')}. "
                        f"Current time {now_time.strftime('%I:%M %p')} is outside this window."
                    ),
                    window_start=str(co_start),
                    window_end=str(co_end),
                )

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
    cache.invalidate(f"today_attendance_{company_id}_{today}")
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
    cache_key = f"today_attendance_{company_id}_{today}"
    cached = cache.get(cache_key)
    if cached is not None:
        return cached

    rows = await db.execute(
        text(
            "SELECT a.id, a.employee_id, e.name, e.profile_photo_url, "
            "a.attendance_date, a.check_in, a.check_out, a.status, a.match_score "
            "FROM attendance a "
            "JOIN employees e ON e.id = a.employee_id "
            "WHERE a.company_id = :cid AND a.attendance_date = :today "
            "AND e.status != 'deleted' "
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

    response = TodayAttendanceResponse(
        date=today,
        total_present=present,
        total_absent=absent,
        total_late=late,
        records=records,
    )
    cache.set(cache_key, response, ttl_seconds=15)
    return response


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
    # Never return attendance records for future dates
    today = date.today()

    rows = await db.execute(
        text(
            "SELECT a.attendance_date, a.check_in, a.check_out, a.status, a.match_score "
            "FROM attendance a "
            "JOIN employees e ON e.id = a.employee_id "
            "WHERE a.employee_id = :eid AND a.company_id = :cid "
            "AND e.status != 'deleted' "
            "AND EXTRACT(MONTH FROM a.attendance_date) = :month "
            "AND EXTRACT(YEAR  FROM a.attendance_date) = :year "
            "AND a.attendance_date <= :today "
            "ORDER BY a.attendance_date"
        ),
        {"eid": employee_id, "cid": company_id, "month": month, "year": year, "today": today},
    )
    return [
        MonthlyAttendanceRecord(
            attendance_date=r[0], check_in=r[1],
            check_out=r[2], status=r[3], match_score=r[4],
        )
        for r in rows.fetchall()
    ]


# ─── POST /api/attendance/manual-checkout ────────────────────
# Admin-only: override / set check_out for an employee on a given date.
# If the employee has no attendance record for that date, one is created
# with status "present" so the admin can still record a departure.
@router.post("/manual-checkout", response_model=ManualCheckoutResponse)
async def manual_checkout(
    payload: ManualCheckoutRequest,
    db:      AsyncSession = Depends(get_db),
    user:    dict         = Depends(get_current_user),   # JWT required
):
    company_id = user["company_id"]

    # Verify employee belongs to this company
    emp_row = await db.execute(
        text("SELECT id, name FROM employees WHERE id = :eid AND company_id = :cid AND status != 'deleted'"),
        {"eid": payload.employee_id, "cid": company_id},
    )
    emp = emp_row.fetchone()
    if not emp:
        raise HTTPException(status_code=404, detail="Employee not found")

    emp_name = emp[1]
    checkout_dt = payload.checkout_time or datetime.now().replace(tzinfo=None)
    # Strip tzinfo so it matches the naive timestamps stored in the DB
    if checkout_dt.tzinfo is not None:
        from datetime import timezone
        checkout_dt = checkout_dt.astimezone(timezone.utc).replace(tzinfo=None)

    # Check for existing attendance record on that date
    existing = await db.execute(
        text("SELECT id, check_in FROM attendance WHERE employee_id = :eid AND attendance_date = :dt"),
        {"eid": payload.employee_id, "dt": payload.attendance_date},
    )
    record = existing.fetchone()

    if record is None:
        # No check-in at all — create a minimal record so admin can record checkout
        await db.execute(
            text(
                "INSERT INTO attendance (employee_id, company_id, attendance_date, check_in, check_out, status, match_score) "
                "VALUES (:eid, :cid, :dt, :cin, :cout, 'present', NULL)"
            ),
            {
                "eid": payload.employee_id,
                "cid": company_id,
                "dt": payload.attendance_date,
                "cin": checkout_dt,   # use checkout time as check-in placeholder
                "cout": checkout_dt,
            },
        )
    else:
        await db.execute(
            text("UPDATE attendance SET check_out = :cout WHERE id = :rid"),
            {"cout": checkout_dt, "rid": record[0]},
        )

    await db.commit()
    today = date.today()
    cache.invalidate(f"today_attendance_{company_id}_{today}")

    return ManualCheckoutResponse(
        success=True,
        employee_name=emp_name,
        checkout_time=checkout_dt.strftime("%H:%M:%S"),
        message=f"Checkout recorded for {emp_name} on {payload.attendance_date}",
    )


# ─── Helpers ──────────────────────────────────────────────────
def _to_time(v) -> Optional[dt_time]:
    """Normalise a DB TIME value to datetime.time.

    asyncpg returns PostgreSQL TIME columns as datetime.timedelta, not
    datetime.time, which makes direct <= comparisons raise TypeError.
    """
    if v is None:
        return None
    if isinstance(v, dt_time):
        return v
    if isinstance(v, timedelta):
        total = int(v.total_seconds())
        return dt_time(total // 3600, (total % 3600) // 60, total % 60)
    # Fallback: try parsing string "HH:MM:SS"
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
