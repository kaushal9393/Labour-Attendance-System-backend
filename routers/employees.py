from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
from typing import List

from core.database import get_db
from core.security import get_current_user
from core.face_service import process_registration_photos
from utils.cloudinary_helper import upload_base64_photo
from models.schemas import EmployeeCreate, EmployeeUpdate, EmployeeResponse, MessageResponse

router = APIRouter(prefix="/api/employees", tags=["Employees"])


@router.get("", response_model=List[EmployeeResponse])
async def list_employees(
    db:   AsyncSession = Depends(get_db),
    user: dict         = Depends(get_current_user),
):
    company_id = user["company_id"]
    rows = await db.execute(
        text(
            "SELECT id, company_id, name, phone, monthly_salary, joining_date, "
            "profile_photo_url, status, created_at "
            "FROM employees WHERE company_id = :cid AND status != 'deleted' "
            "ORDER BY name"
        ),
        {"cid": company_id},
    )
    employees = rows.fetchall()
    return [
        EmployeeResponse(
            id=r[0], company_id=r[1], name=r[2], phone=r[3],
            monthly_salary=r[4], joining_date=r[5],
            profile_photo_url=r[6], status=r[7], created_at=r[8],
        )
        for r in employees
    ]


@router.post("/register", response_model=MessageResponse, status_code=status.HTTP_201_CREATED)
async def register_employee(
    payload: EmployeeCreate,
    db:      AsyncSession = Depends(get_db),
    user:    dict         = Depends(get_current_user),
):
    company_id = user["company_id"]

    # 1. Generate ArcFace embeddings from 25 photos
    try:
        face_data = process_registration_photos(payload.photos)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    # 2. Upload profile photo to Cloudinary
    profile_url = upload_base64_photo(face_data["profile_b64"])

    # 3. Insert employee
    result = await db.execute(
        text(
            "INSERT INTO employees (company_id, name, phone, monthly_salary, joining_date, profile_photo_url) "
            "VALUES (:cid, :name, :phone, :salary, :jdate, :photo_url) RETURNING id"
        ),
        {
            "cid":       company_id,
            "name":      payload.name,
            "phone":     payload.phone,
            "salary":    float(payload.monthly_salary),
            "jdate":     payload.joining_date,
            "photo_url": profile_url,
        },
    )
    employee_id = result.scalar_one()

    # 4. Store 3 face vectors (front / left / right)
    for angle in ("front", "left", "right"):
        embedding = face_data[angle]
        # Convert list to pgvector literal  '[0.1, 0.2, ...]'
        vec_str = "[" + ",".join(str(x) for x in embedding) + "]"
        await db.execute(
            text(
                "INSERT INTO face_vectors (employee_id, face_vector, angle_type) "
                "VALUES (:eid, CAST(:vec AS vector), :angle)"
            ),
            {"eid": employee_id, "vec": vec_str, "angle": angle},
        )

    await db.commit()
    return MessageResponse(message=f"Employee '{payload.name}' registered successfully")


@router.put("/{employee_id}", response_model=MessageResponse)
async def update_employee(
    employee_id: int,
    payload:     EmployeeUpdate,
    db:          AsyncSession = Depends(get_db),
    user:        dict         = Depends(get_current_user),
):
    company_id = user["company_id"]

    # Build dynamic SET clause
    updates = {}
    if payload.name           is not None: updates["name"]           = payload.name
    if payload.phone          is not None: updates["phone"]          = payload.phone
    if payload.monthly_salary is not None: updates["monthly_salary"] = float(payload.monthly_salary)
    if payload.joining_date   is not None: updates["joining_date"]   = payload.joining_date
    if payload.status         is not None: updates["status"]         = payload.status

    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")

    set_clause = ", ".join(f"{k} = :{k}" for k in updates)
    updates["eid"] = employee_id
    updates["cid"] = company_id

    await db.execute(
        text(f"UPDATE employees SET {set_clause} WHERE id = :eid AND company_id = :cid"),
        updates,
    )
    await db.commit()
    return MessageResponse(message="Employee updated successfully")


@router.delete("/{employee_id}", response_model=MessageResponse)
async def delete_employee(
    employee_id: int,
    db:          AsyncSession = Depends(get_db),
    user:        dict         = Depends(get_current_user),
):
    company_id = user["company_id"]
    await db.execute(
        text("UPDATE employees SET status = 'inactive' WHERE id = :eid AND company_id = :cid"),
        {"eid": employee_id, "cid": company_id},
    )
    await db.commit()
    return MessageResponse(message="Employee deactivated")
