import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from core.database import get_db
from core.security import verify_password, hash_password, create_access_token
from models.schemas import (
    LoginRequest, LoginResponse,
    SignupRequest, SignupResponse,
    CheckCompanyCodeResponse,
)

logger = logging.getLogger("garage_api.auth")
router = APIRouter(prefix="/api/auth", tags=["Auth"])


@router.post("/login", response_model=LoginResponse)
async def login(payload: LoginRequest, db: AsyncSession = Depends(get_db)):
    """Email + password login. company_code is no longer required — the
    admin's company is looked up via the join."""
    row = await db.execute(
        text(
            "SELECT a.id, a.name, a.password_hash, "
            "c.id, c.name, c.company_code, c.plan "
            "FROM admins a "
            "JOIN companies c ON c.id = a.company_id "
            "WHERE a.email = :email"
        ),
        {"email": payload.email},
    )
    record = row.fetchone()
    if not record:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Invalid credentials")

    admin_id, admin_name, password_hash, company_id, company_name, company_code, plan = record

    if not verify_password(payload.password, password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="Invalid credentials")

    token = create_access_token({
        "sub":          payload.email,
        "company_id":   company_id,
        "admin_id":     admin_id,
        "admin_name":   admin_name,
        "company_code": company_code,
    })

    return LoginResponse(
        token=token,
        admin_name=admin_name,
        company_name=company_name,
        company_id=company_id,
        company_code=company_code,
        plan=plan or "free",
    )


@router.get("/check-code", response_model=CheckCompanyCodeResponse)
async def check_company_code(code: str, db: AsyncSession = Depends(get_db)):
    """Used by the signup form to tell the user whether their chosen
    company_code is still free."""
    code = code.strip().upper()
    row = await db.execute(
        text("SELECT 1 FROM companies WHERE company_code = :code"),
        {"code": code},
    )
    exists = row.fetchone() is not None
    return CheckCompanyCodeResponse(available=not exists, company_code=code)


@router.post("/signup", response_model=SignupResponse,
             status_code=status.HTTP_201_CREATED)
async def signup(payload: SignupRequest, db: AsyncSession = Depends(get_db)):
    """Create a new tenant: company + first admin + default settings."""
    # 1. Reject duplicate email or company_code up front so we don't burn
    #    a savepoint on a guaranteed failure.
    dup = await db.execute(
        text(
            "SELECT "
            " (SELECT 1 FROM admins    WHERE email        = :email) AS email_taken, "
            " (SELECT 1 FROM companies WHERE company_code = :code)  AS code_taken"
        ),
        {"email": payload.email, "code": payload.company_code},
    )
    email_taken, code_taken = dup.fetchone()
    if email_taken:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                            detail="Email already registered")
    if code_taken:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                            detail="Company code already taken")

    # 2. Create the company.
    company_row = await db.execute(
        text(
            "INSERT INTO companies (name, company_code, owner_phone, plan) "
            "VALUES (:name, :code, :phone, 'free') RETURNING id"
        ),
        {
            "name":  payload.business_name,
            "code":  payload.company_code,
            "phone": payload.phone,
        },
    )
    company_id = company_row.scalar_one()

    # 3. Create the admin user.
    admin_row = await db.execute(
        text(
            "INSERT INTO admins (company_id, name, email, password_hash) "
            "VALUES (:cid, :name, :email, :pw) RETURNING id"
        ),
        {
            "cid":   company_id,
            "name":  payload.owner_name,
            "email": payload.email,
            "pw":    hash_password(payload.password),
        },
    )
    admin_id = admin_row.scalar_one()

    # 4. Default settings row.
    await db.execute(
        text(
            "INSERT INTO settings (company_id) VALUES (:cid) "
            "ON CONFLICT (company_id) DO NOTHING"
        ),
        {"cid": company_id},
    )

    await db.commit()
    logger.info(f"[Signup] new tenant: {payload.company_code} (id={company_id})")

    token = create_access_token({
        "sub":          payload.email,
        "company_id":   company_id,
        "admin_id":     admin_id,
        "admin_name":   payload.owner_name,
        "company_code": payload.company_code,
    })

    return SignupResponse(
        token=token,
        admin_name=payload.owner_name,
        company_name=payload.business_name,
        company_id=company_id,
        company_code=payload.company_code,
        plan="free",
    )
