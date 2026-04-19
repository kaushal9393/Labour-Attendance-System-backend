from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
import calendar

from core.database import get_db
from core.security import get_current_user
from models.schemas import MonthlySummaryResponse, MonthlySummaryEmployee

router = APIRouter(prefix="/api/reports", tags=["Reports"])


@router.get("/monthly-summary", response_model=MonthlySummaryResponse)
async def monthly_summary(
    month: int = Query(..., ge=1, le=12),
    year:  int = Query(..., ge=2020),
    db:   AsyncSession = Depends(get_db),
    user: dict         = Depends(get_current_user),
):
    company_id = user["company_id"]

    # Get settings
    settings_row = await db.execute(
        text("SELECT working_days_per_week FROM settings WHERE company_id = :cid"),
        {"cid": company_id},
    )
    settings = settings_row.fetchone()
    days_per_week = settings[0] if settings else 6
    working_days  = _count_working_days(year, month, days_per_week)

    rows = await db.execute(
        text(
            "SELECT e.id, e.name, e.monthly_salary, "
            "  COUNT(*) FILTER (WHERE a.status IN ('present','late')) AS present_days, "
            "  COUNT(*) FILTER (WHERE a.status = 'absent')            AS absent_days, "
            "  COUNT(*) FILTER (WHERE a.status = 'late')              AS late_days "
            "FROM employees e "
            "LEFT JOIN attendance a ON a.employee_id = e.id "
            "  AND EXTRACT(MONTH FROM a.attendance_date) = :month "
            "  AND EXTRACT(YEAR  FROM a.attendance_date) = :year "
            "WHERE e.company_id = :cid AND e.status = 'active' "
            "GROUP BY e.id, e.name, e.monthly_salary "
            "ORDER BY e.name"
        ),
        {"cid": company_id, "month": month, "year": year},
    )

    employees = []
    for r in rows.fetchall():
        emp_id, emp_name, monthly_salary, present, absent, late = r
        per_day   = float(monthly_salary) / working_days if working_days else 0
        deduction = int(absent) * per_day
        net_pay   = float(monthly_salary) - deduction
        employees.append(MonthlySummaryEmployee(
            employee_id=emp_id,
            employee_name=emp_name,
            present_days=int(present),
            absent_days=int(absent),
            late_days=int(late),
            net_pay=round(net_pay, 2),
        ))

    return MonthlySummaryResponse(month=month, year=year, employees=employees)


def _count_working_days(year: int, month: int, days_per_week: int) -> int:
    _, total_days = calendar.monthrange(year, month)
    exclude = [6] if days_per_week == 6 else ([5, 6] if days_per_week == 5 else [])
    return sum(1 for d in range(1, total_days + 1) if calendar.weekday(year, month, d) not in exclude)
