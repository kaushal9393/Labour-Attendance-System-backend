import calendar
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
    settings = settings_row.fetchone()
    days_per_week = settings[0] if settings else 6

    # 3. Calculate working days in the month
    working_days = _count_working_days(year, month, days_per_week)

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
    absent_days  = max(0, working_days - present_days)

    # 5. Salary math
    per_day_salary   = float(monthly_salary) / working_days if working_days > 0 else 0
    deduction_amount = absent_days * per_day_salary
    net_pay          = float(monthly_salary) - deduction_amount

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


def _count_working_days(year: int, month: int, days_per_week: int) -> int:
    """
    Count working days in a month.
    days_per_week=6 → Mon-Sat (exclude Sunday = weekday 6)
    days_per_week=5 → Mon-Fri (exclude Sat=5, Sun=6)
    """
    _, total_days = calendar.monthrange(year, month)
    exclude = []
    if days_per_week == 6:
        exclude = [6]          # Sunday
    elif days_per_week == 5:
        exclude = [5, 6]       # Sat + Sun

    count = 0
    for day in range(1, total_days + 1):
        wd = calendar.weekday(year, month, day)
        if wd not in exclude:
            count += 1
    return count
