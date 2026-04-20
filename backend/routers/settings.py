from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from core.database import get_db
from core.security import get_current_user
from models.schemas import SettingsResponse, SettingsUpdate

router = APIRouter(prefix="/api/settings", tags=["Settings"])


@router.get("", response_model=SettingsResponse)
async def get_settings(
    db:   AsyncSession = Depends(get_db),
    user: dict         = Depends(get_current_user),
):
    company_id = user["company_id"]
    row = await db.execute(
        text(
            "SELECT id, company_id, work_start_time, work_end_time, "
            "late_threshold_minutes, working_days_per_week "
            "FROM settings WHERE company_id = :cid"
        ),
        {"cid": company_id},
    )
    s = row.fetchone()
    if not s:
        raise HTTPException(status_code=404, detail="Settings not found")
    return SettingsResponse(
        id=s[0], company_id=s[1],
        work_start_time=s[2], work_end_time=s[3],
        late_threshold_minutes=s[4], working_days_per_week=s[5],
    )


@router.put("", response_model=SettingsResponse)
async def update_settings(
    payload: SettingsUpdate,
    db:      AsyncSession = Depends(get_db),
    user:    dict         = Depends(get_current_user),
):
    company_id = user["company_id"]

    updates = {}
    if payload.work_start_time        is not None: updates["work_start_time"]        = payload.work_start_time
    if payload.work_end_time          is not None: updates["work_end_time"]          = payload.work_end_time
    if payload.late_threshold_minutes is not None: updates["late_threshold_minutes"] = payload.late_threshold_minutes
    if payload.working_days_per_week  is not None: updates["working_days_per_week"]  = payload.working_days_per_week

    if updates:
        set_clause = ", ".join(f"{k} = :{k}" for k in updates)
        updates["cid"] = company_id
        await db.execute(
            text(f"UPDATE settings SET {set_clause} WHERE company_id = :cid"),
            updates,
        )
        await db.commit()

    return await get_settings(db=db, user=user)


@router.post("/init", status_code=201)
async def init_settings(
    db:   AsyncSession = Depends(get_db),
    user: dict         = Depends(get_current_user),
):
    """Create default settings row if it doesn't exist."""
    company_id = user["company_id"]
    await db.execute(
        text("INSERT INTO settings (company_id) VALUES (:cid) ON CONFLICT (company_id) DO NOTHING"),
        {"cid": company_id},
    )
    await db.commit()
    return {"message": "Settings initialised"}
