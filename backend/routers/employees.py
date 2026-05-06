from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
from typing import List
import json

from core.database import get_db
from core.security import get_current_user
from core.cache import cache
from core.aws_rekognition_service import register_employee_faces, delete_faces_from_list, update_face_userdata
from utils.cloudinary_helper import upload_base64_photo
from models.schemas import EmployeeCreate, EmployeeUpdate, EmployeeResponse, MessageResponse

router = APIRouter(prefix="/api/employees", tags=["Employees"])


@router.get("", response_model=List[EmployeeResponse])
async def list_employees(
    db:   AsyncSession = Depends(get_db),
    user: dict         = Depends(get_current_user),
):
    company_id = user["company_id"]
    cache_key = f"employees_list_{company_id}"
    cached = cache.get(cache_key)
    if cached is not None:
        return cached

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
    result = [
        EmployeeResponse(
            id=r[0], company_id=r[1], name=r[2], phone=r[3],
            monthly_salary=r[4], joining_date=r[5],
            profile_photo_url=r[6], status=r[7], created_at=r[8],
        )
        for r in employees
    ]
    cache.set(cache_key, result, ttl_seconds=30)
    return result


@router.post("/register", response_model=MessageResponse, status_code=status.HTTP_201_CREATED)
async def register_employee(
    payload: EmployeeCreate,
    db:      AsyncSession = Depends(get_db),
    user:    dict         = Depends(get_current_user),
):
    company_id = user["company_id"]

    # 1. Index photos into AWS Rekognition collection — use "pending" as temp ExternalImageId
    try:
        persisted_face_ids = register_employee_faces(
            company_id=company_id,
            employee_id_placeholder="pending",
            photos=payload.photos,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"AWS Rekognition registration failed: {exc}")

    # 2. Upload profile photo to Cloudinary
    profile_url = upload_base64_photo(payload.photos[0])

    # 3. Insert employee — store persisted_face_ids as JSON
    result = await db.execute(
        text(
            "INSERT INTO employees (company_id, name, phone, monthly_salary, joining_date, "
            "profile_photo_url, azure_person_id) "
            "VALUES (:cid, :name, :phone, :salary, :jdate, :photo_url, :face_ids) RETURNING id"
        ),
        {
            "cid":      company_id,
            "name":     payload.name,
            "phone":    payload.phone,
            "salary":   float(payload.monthly_salary),
            "jdate":    payload.joining_date,
            "photo_url": profile_url,
            "face_ids": json.dumps(persisted_face_ids),
        },
    )
    employee_id = result.scalar_one()
    await db.commit()

    # 4. (No-op for AWS — DB already maps face_ids -> employee_id)
    for fid in persisted_face_ids:
        try:
            update_face_userdata(company_id, fid, employee_id)
        except Exception:
            pass

    cache.invalidate(f"employees_list_{company_id}")
    return MessageResponse(message=f"Employee '{payload.name}' registered successfully")


@router.put("/{employee_id}", response_model=MessageResponse)
async def update_employee(
    employee_id: int,
    payload:     EmployeeUpdate,
    db:          AsyncSession = Depends(get_db),
    user:        dict         = Depends(get_current_user),
):
    company_id = user["company_id"]

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
    cache.invalidate(f"employees_list_{company_id}")
    return MessageResponse(message="Employee updated successfully")


@router.delete("/{employee_id}", response_model=MessageResponse)
async def delete_employee(
    employee_id: int,
    db:          AsyncSession = Depends(get_db),
    user:        dict         = Depends(get_current_user),
):
    company_id = user["company_id"]

    row = await db.execute(
        text("SELECT id, azure_person_id FROM employees WHERE id = :eid AND company_id = :cid"),
        {"eid": employee_id, "cid": company_id},
    )
    emp = row.fetchone()
    if not emp:
        raise HTTPException(status_code=404, detail="Employee not found")

    # Delete faces from AWS Rekognition collection
    face_ids_json = emp[1]
    if face_ids_json:
        try:
            face_ids = json.loads(face_ids_json)
            delete_faces_from_list(company_id, face_ids)
        except Exception:
            pass

    # Delete all related DB data
    await db.execute(text("DELETE FROM salary_records WHERE employee_id = :eid"), {"eid": employee_id})
    await db.execute(text("DELETE FROM attendance    WHERE employee_id = :eid"), {"eid": employee_id})
    await db.execute(text("DELETE FROM face_vectors  WHERE employee_id = :eid"), {"eid": employee_id})
    await db.execute(text("DELETE FROM employees     WHERE id = :eid AND company_id = :cid"),
                     {"eid": employee_id, "cid": company_id})

    await db.commit()
    cache.invalidate(f"employees_list_{company_id}")
    return MessageResponse(message="Employee deleted")
