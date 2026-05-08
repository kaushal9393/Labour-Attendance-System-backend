"""
main.py — Garage Attendance System API
FastAPI + Neon PostgreSQL + AWS Rekognition
"""
import os
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.staticfiles import StaticFiles
from dotenv import load_dotenv

from core.database import ping_db, AsyncSessionLocal
from routers import auth, employees, attendance, salary, reports, settings as settings_router, notifications as notifications_router, working_days as working_days_router, liveness as liveness_router

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("garage_api")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # ── Startup ──
    logger.info("Starting Garage Attendance API…")
    db_ok = await ping_db()
    if db_ok:
        logger.info("✅ Database connected")
    else:
        logger.warning("⚠️  Database connection failed — check DATABASE_URL")

    # Run DB migrations to add any missing columns
    try:
        from sqlalchemy import text as _text
        async with AsyncSessionLocal() as _session:
            await _session.execute(_text("""
                ALTER TABLE settings
                    ADD COLUMN IF NOT EXISTS checkin_window_start  TIME,
                    ADD COLUMN IF NOT EXISTS checkin_window_end    TIME,
                    ADD COLUMN IF NOT EXISTS checkout_window_start TIME,
                    ADD COLUMN IF NOT EXISTS checkout_window_end   TIME
            """))
            # Back-fill NULL window columns with sensible defaults so the
            # time-window enforcement is active for existing settings rows.
            await _session.execute(_text("""
                UPDATE settings SET
                    checkin_window_start  = '08:45:00' WHERE checkin_window_start  IS NULL
            """))
            await _session.execute(_text("""
                UPDATE settings SET
                    checkin_window_end    = '10:00:00' WHERE checkin_window_end    IS NULL
            """))
            await _session.execute(_text("""
                UPDATE settings SET
                    checkout_window_start = '17:00:00' WHERE checkout_window_start IS NULL
            """))
            await _session.execute(_text("""
                UPDATE settings SET
                    checkout_window_end   = '19:00:00' WHERE checkout_window_end   IS NULL
            """))
            await _session.execute(_text("""
                CREATE TABLE IF NOT EXISTS monthly_working_days (
                    id         SERIAL PRIMARY KEY,
                    company_id INTEGER NOT NULL,
                    month      INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
                    year       INTEGER NOT NULL,
                    working_days INTEGER NOT NULL,
                    UNIQUE (company_id, month, year)
                )
            """))
            # Face provider — column name kept as azure_person_id for backwards
            # compatibility; now stores AWS Rekognition FaceIds (JSON array).
            await _session.execute(_text("""
                ALTER TABLE employees
                    ADD COLUMN IF NOT EXISTS azure_person_id TEXT
            """))
            # Multi-tenant SaaS columns on companies
            await _session.execute(_text("""
                ALTER TABLE companies
                    ADD COLUMN IF NOT EXISTS owner_phone VARCHAR(20),
                    ADD COLUMN IF NOT EXISTS plan        VARCHAR(20) DEFAULT 'free',
                    ADD COLUMN IF NOT EXISTS status      VARCHAR(20) DEFAULT 'active'
            """))
            await _session.execute(_text("UPDATE companies SET plan='free' WHERE plan IS NULL"))
            # One-time tenant reset: drop the seeded GARAGE2024 demo data
            # so the SaaS launch starts on a clean slate. Idempotent — only
            # fires while the demo company still exists.
            if os.getenv("RESET_DEMO_TENANT", "1") == "1":
                await _session.execute(_text("""
                    DELETE FROM salary_records
                     WHERE employee_id IN (SELECT id FROM employees WHERE company_id = 1)
                """))
                await _session.execute(_text("""
                    DELETE FROM attendance
                     WHERE company_id = 1
                """))
                await _session.execute(_text("""
                    DELETE FROM face_vectors
                     WHERE employee_id IN (SELECT id FROM employees WHERE company_id = 1)
                """))
                await _session.execute(_text("""
                    DELETE FROM employees WHERE company_id = 1
                """))
                await _session.execute(_text("""
                    DELETE FROM monthly_working_days WHERE company_id = 1
                """))
                await _session.execute(_text("""
                    DELETE FROM settings WHERE company_id = 1
                """))
                await _session.execute(_text("""
                    DELETE FROM admins   WHERE company_id = 1
                """))
                await _session.execute(_text("""
                    DELETE FROM companies WHERE id = 1 AND company_code = 'GARAGE2024'
                """))
            await _session.commit()
        logger.info("✅ DB migration complete")
    except Exception as _e:
        logger.warning(f"⚠️ DB migration warning: {_e}")

    # Verify AWS Rekognition credentials at startup
    try:
        from core.aws_rekognition_service import (
            AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_KEY,
        )
        if AWS_ACCESS_KEY_ID and AWS_SECRET_KEY:
            logger.info(f"✅ AWS Rekognition configured (region={AWS_REGION})")
        else:
            logger.warning("⚠️ AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY not set")
    except Exception as e:
        logger.warning(f"⚠️ AWS Rekognition check failed: {e}")
    yield
    # ── Shutdown ──
    logger.info("Shutting down…")


app = FastAPI(
    title="Garage Attendance System API",
    description="Face-recognition attendance system with ArcFace + MediaPipe liveness",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

# ── Compression (reduces response size 60-80%) ────────────────
app.add_middleware(GZipMiddleware, minimum_size=500)

# ── CORS ──────────────────────────────────────────────────────
origins = os.getenv("CORS_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Health checks (BEFORE routers) ───────────────────────────
@app.api_route("/", methods=["GET", "HEAD"], tags=["Health"])
async def root():
    return JSONResponse({"status": "ok"})

@app.api_route("/ping", methods=["GET", "HEAD"], tags=["Health"])
async def ping():
    return JSONResponse({"status": "ok"})

@app.api_route("/health", methods=["GET", "HEAD"], tags=["Health"])
async def health():
    return JSONResponse({"status": "ok", "service": "Garage Attendance API"})

    
# ── Routers (AFTER health checks) ────────────────────────────
app.include_router(auth.router)
app.include_router(employees.router)
app.include_router(attendance.router)
app.include_router(salary.router)
app.include_router(reports.router)
app.include_router(settings_router.router)
app.include_router(notifications_router.router)
app.include_router(working_days_router.router)
app.include_router(liveness_router.router)

# ── Liveness static UI (React build) ──
_liveness_dir = os.path.join(os.path.dirname(__file__), "static", "liveness")
if os.path.isdir(_liveness_dir):
    app.mount("/liveness", StaticFiles(directory=_liveness_dir, html=True), name="liveness")