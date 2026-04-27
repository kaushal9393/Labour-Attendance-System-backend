import calendar
import datetime
from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from core.database import get_db
from core.security import get_current_user
from models.schemas import SalaryResponse

router = APIRouter(prefix="/api/salary", tags=["Salary"])


@router.get("/monthly", response_model=SalaryResponse)
async def monthly_salary(
    employee_id: int = Query(...),
    month:       int = Query(..., ge=1, le=12),
    year:        int = Query(..., ge=2020),
    db:   AsyncSession = Depends(get_db),
    user: dict         = Depends(get_current_user),
):
    company_id = user["company_id"]

    # 1. Employee details
    emp_row = await db.execute(
        text("SELECT name, monthly_salary FROM employees WHERE id = :eid AND company_id = :cid"),
        {"eid": employee_id, "cid": company_id},
    )
    emp = emp_row.fetchone()
    if not emp:
        raise HTTPException(status_code=404, detail="Employee not found")
    emp_name, monthly_salary = emp

    # 2. Settings
    settings_row = await db.execute(
        text("SELECT working_days_per_week FROM settings WHERE company_id = :cid"),
        {"cid": company_id},
    )
    settings_fetched = settings_row.fetchone()
    days_per_week = settings_fetched[0] if settings_fetched else 6

    # 3. Check if admin has manually set working days for this month
    manual_row = await db.execute(
        text("SELECT working_days FROM monthly_working_days WHERE company_id = :cid AND month = :month AND year = :year"),
        {"cid": company_id, "month": month, "year": year},
    )
    manual = manual_row.fetchone()

    today = datetime.date.today()
    if manual:
        working_days = manual[0]
    else:
        if month == today.month and year == today.year:
            count_till = today
        else:
            last_day = calendar.monthrange(year, month)[1]
            count_till = datetime.date(year, month, last_day)
        working_days = _count_working_days(
            start=datetime.date(year, month, 1),
            end=count_till,
            days_per_week=days_per_week,
        )

    # 4. Count attendance
    att_row = await db.execute(
        text(
            "SELECT "
            "  COUNT(*) FILTER (WHERE status IN ('present','late')) AS present_days, "
            "  COUNT(*) FILTER (WHERE status = 'late')              AS late_days "
            "FROM attendance "
            "WHERE employee_id = :eid "
            "  AND EXTRACT(MONTH FROM attendance_date) = :month "
            "  AND EXTRACT(YEAR  FROM attendance_date) = :year"
        ),
        {"eid": employee_id, "month": month, "year": year},
    )
    att = att_row.fetchone()
    present_days = int(att[0]) if att else 0
    late_days    = int(att[1]) if att else 0
    absent_days  = max(0, working_days - present_days - late_days)

    # 5. Salary math — use manual total if set, else auto-calculate full month
    if manual:
        total_month_working_days = manual[0]
    else:
        total_month_working_days = _count_working_days(
            start=datetime.date(year, month, 1),
            end=datetime.date(year, month, calendar.monthrange(year, month)[1]),
            days_per_week=days_per_week,
        )
    per_day_salary   = float(monthly_salary) / total_month_working_days if total_month_working_days > 0 else 0
    net_pay          = (present_days + late_days) * per_day_salary
    deduction_amount = float(monthly_salary) - net_pay

    # 6. Upsert salary record
    await db.execute(
        text(
            "INSERT INTO salary_records "
            "(employee_id, month, year, working_days, present_days, late_days, absent_days, "
            " monthly_salary, per_day_salary, deduction_amount, net_pay) "
            "VALUES (:eid,:month,:year,:wd,:pd,:ld,:ad,:ms,:pds,:ded,:np) "
            "ON CONFLICT (employee_id, month, year) DO UPDATE SET "
            "  present_days=EXCLUDED.present_days, late_days=EXCLUDED.late_days, "
            "  absent_days=EXCLUDED.absent_days, deduction_amount=EXCLUDED.deduction_amount, "
            "  net_pay=EXCLUDED.net_pay, generated_at=NOW()"
        ),
        {
            "eid": employee_id, "month": month, "year": year,
            "wd": working_days, "pd": present_days, "ld": late_days, "ad": absent_days,
            "ms": float(monthly_salary), "pds": round(per_day_salary, 2),
            "ded": round(deduction_amount, 2), "np": round(net_pay, 2),
        },
    )
    await db.commit()

    return SalaryResponse(
        employee_id=employee_id,
        employee_name=emp_name,
        month=month,
        year=year,
        monthly_salary=monthly_salary,
        working_days=working_days,
        present_days=present_days,
        late_days=late_days,
        absent_days=absent_days,
        per_day_salary=round(per_day_salary, 2),
        deduction_amount=round(deduction_amount, 2),
        net_pay=round(net_pay, 2),
    )


def _count_working_days(start: datetime.date, end: datetime.date, days_per_week: int) -> int:
    count = 0
    current = start
    while current <= end:
        if days_per_week == 6:
            if current.weekday() != 6:
                count += 1
        else:
            if current.weekday() < 5:
                count += 1
        current += datetime.timedelta(days=1)
    return count
