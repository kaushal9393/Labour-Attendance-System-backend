from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from core.database import get_db
from core.security import verify_password, create_access_token
from models.schemas import LoginRequest, LoginResponse

router = APIRouter(prefix="/api/auth", tags=["Auth"])


@router.post("/login", response_model=LoginResponse)
async def login(payload: LoginRequest, db: AsyncSession = Depends(get_db)):
    # 1. Find company by code
    company_row = await db.execute(
        text("SELECT id, name FROM companies WHERE company_code = :code"),
        {"code": payload.company_code},
    )
    company = company_row.fetchone()
    if not company:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid company code")

    company_id, company_name = company

    # 2. Find admin by email + company
    admin_row = await db.execute(
        text(
            "SELECT id, name, password_hash FROM admins "
            "WHERE email = :email AND company_id = :cid"
        ),
        {"email": payload.email, "cid": company_id},
    )
    admin = admin_row.fetchone()
    if not admin:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

    admin_id, admin_name, password_hash = admin

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
