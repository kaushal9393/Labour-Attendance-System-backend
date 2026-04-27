import datetime
from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from core.database import get_db
from core.security import get_current_user

router = APIRouter(prefix="/api/working-days", tags=["Working Days"])


@router.get("")
async def get_working_days(
    month: int = Query(..., ge=1, le=12),
    year:  int = Query(..., ge=2020),
    db:    AsyncSession = Depends(get_db),
    user:  dict         = Depends(get_current_user),
):
    company_id = user["company_id"]
    row = await db.execute(
        text(
            "SELECT working_days FROM monthly_working_days "
            "WHERE company_id = :cid AND month = :month AND year = :year"
        ),
        {"cid": company_id, "month": month, "year": year},
    )
    r = row.fetchone()
    if not r:
        return {"month": month, "year": year, "working_days": None}
    return {"month": month, "year": year, "working_days": r[0]}


@router.put("")
async def set_working_days(
    payload: dict,
    db:   AsyncSession = Depends(get_db),
    user: dict         = Depends(get_current_user),
):
    company_id   = user["company_id"]
    month        = payload.get("month")
    year         = payload.get("year")
    working_days = payload.get("working_days")

    if not all([month, year, working_days is not None]):
        raise HTTPException(status_code=422, detail="month, year, working_days required")
    if not (1 <= month <= 12):
        raise HTTPException(status_code=422, detail="month must be 1-12")
    if not (2020 <= year <= 2100):
        raise HTTPException(status_code=422, detail="invalid year")
    if not (1 <= working_days <= 31):
        raise HTTPException(status_code=422, detail="working_days must be 1-31")

    await db.execute(
        text(
            "INSERT INTO monthly_working_days (company_id, month, year, working_days) "
            "VALUES (:cid, :month, :year, :wd) "
            "ON CONFLICT (company_id, month, year) DO UPDATE SET working_days = EXCLUDED.working_days"
        ),
        {"cid": company_id, "month": month, "year": year, "wd": working_days},
    )
    await db.commit()
    return {"month": month, "year": year, "working_days": working_days}
