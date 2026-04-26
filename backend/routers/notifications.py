from datetime import datetime, date, time as dt_time, timedelta
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from core.database import get_db
from core.security import get_current_user

router = APIRouter(prefix="/api/notifications", tags=["Notifications"])


@router.get("")
async def get_notifications(
    db:   AsyncSession = Depends(get_db),
    user: dict         = Depends(get_current_user),
):
    from datetime import timezone
    _IST = timezone(timedelta(hours=5, minutes=30))
    company_id = user["company_id"]
    today      = datetime.now(tz=_IST).date()

    # ── Work start time + late threshold ──────────────────────────
    settings_row = await db.execute(
        text("SELECT work_start_time, late_threshold_minutes FROM settings WHERE company_id = :cid"),
        {"cid": company_id},
    )
    settings = settings_row.fetchone()
    work_start      = _to_time(settings[0]) if settings else None
    late_threshold  = settings[1] if settings else 15

    notifications = []

    # ── 1. Late arrivals today ─────────────────────────────────────
    late_rows = await db.execute(
        text("""
            SELECT e.name, a.check_in
            FROM attendance a
            JOIN employees e ON e.id = a.employee_id
            WHERE a.company_id = :cid
              AND a.attendance_date = :today
              AND a.status = 'late'
            ORDER BY a.check_in DESC
        """),
        {"cid": company_id, "today": today},
    )
    for row in late_rows.fetchall():
        name, check_in = row
        if check_in and work_start:
            late_dt = datetime.combine(today, work_start) + timedelta(minutes=late_threshold)
            delta   = int((check_in - late_dt).total_seconds() / 60)
            mins_late = max(delta, 1)
            check_in_fmt = check_in.strftime("%I:%M %p")
            notifications.append({
                "title": "Late Arrival",
                "body":  f"{name} checked in at {check_in_fmt} ({mins_late} min late)",
                "time":  check_in.isoformat(),
                "type":  "late",
            })
        else:
            notifications.append({
                "title": "Late Arrival",
                "body":  f"{name} arrived late today",
                "time":  datetime.combine(today, check_in.time() if check_in else datetime.now().time()).isoformat(),
                "type":  "late",
            })

    # ── 2. Normal check-ins today ──────────────────────────────────
    checkin_rows = await db.execute(
        text("""
            SELECT e.name, a.check_in
            FROM attendance a
            JOIN employees e ON e.id = a.employee_id
            WHERE a.company_id = :cid
              AND a.attendance_date = :today
              AND a.status = 'present'
            ORDER BY a.check_in DESC
            LIMIT 10
        """),
        {"cid": company_id, "today": today},
    )
    for row in checkin_rows.fetchall():
        name, check_in = row
        if check_in:
            notifications.append({
                "title": "Check-In",
                "body":  f"{name} checked in at {check_in.strftime('%I:%M %p')}",
                "time":  check_in.isoformat(),
                "type":  "checkin",
            })

    # ── 3. Check-outs today ────────────────────────────────────────
    checkout_rows = await db.execute(
        text("""
            SELECT e.name, a.check_out
            FROM attendance a
            JOIN employees e ON e.id = a.employee_id
            WHERE a.company_id = :cid
              AND a.attendance_date = :today
              AND a.check_out IS NOT NULL
            ORDER BY a.check_out DESC
            LIMIT 10
        """),
        {"cid": company_id, "today": today},
    )
    for row in checkout_rows.fetchall():
        name, check_out = row
        if check_out:
            notifications.append({
                "title": "Check-Out",
                "body":  f"{name} checked out at {check_out.strftime('%I:%M %p')}",
                "time":  check_out.isoformat(),
                "type":  "checkout",
            })

    # ── 4. Absent alert ────────────────────────────────────────────
    absent_row = await db.execute(
        text("""
            SELECT COUNT(*) FROM employees
            WHERE company_id = :cid AND status = 'active'
              AND id NOT IN (
                SELECT employee_id FROM attendance
                WHERE company_id = :cid AND attendance_date = :today
              )
        """),
        {"cid": company_id, "today": today},
    )
    absent_count = absent_row.scalar() or 0
    if absent_count > 0:
        # Generate the alert at 1 hour after work start (or now if no setting)
        alert_time = (
            datetime.combine(today, work_start) + timedelta(hours=1)
            if work_start
            else datetime.now()
        )
        notifications.append({
            "title": "Absent Alert",
            "body":  f"{absent_count} employee{'s' if absent_count > 1 else ''} {'have' if absent_count > 1 else 'has'} not checked in yet today",
            "time":  alert_time.isoformat(),
            "type":  "absent",
        })

    # Sort newest first
    notifications.sort(key=lambda n: n["time"], reverse=True)

    return {"notifications": notifications}


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
