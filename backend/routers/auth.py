from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from core.database import get_db
from core.security import verify_password, create_access_token
from models.schemas import LoginRequest, LoginResponse

router = APIRouter(prefix="/api/auth", tags=["Auth"])


@router.post("/login", response_model=LoginResponse)
async def login(payload: LoginRequest, db: AsyncSession = Depends(get_db)):
    # Single JOIN — fetch company + admin in one DB round trip
    row = await db.execute(
        text(
            "SELECT a.id, a.name, a.password_hash, c.id, c.name "
            "FROM admins a "
            "JOIN companies c ON c.id = a.company_id "
            "WHERE c.company_code = :code AND a.email = :email"
        ),
        {"code": payload.company_code, "email": payload.email},
    )
    record = row.fetchone()
    if not record:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

    admin_id, admin_name, password_hash, company_id, company_name = record

    # 3. Verify password
    if not verify_password(payload.password, password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

    # 4. Create JWT
    token = create_access_token({
        "sub":        payload.email,
        "company_id": company_id,
        "admin_id":   admin_id,
        "admin_name": admin_name,
    })

    return LoginResponse(
        token=token,
        admin_name=admin_name,
        company_name=company_name,
        company_id=company_id,
    )
