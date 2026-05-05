"""
main.py — Garage Attendance System API
FastAPI + Neon PostgreSQL + Azure Face API
"""
import os
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from dotenv import load_dotenv

from core.database import ping_db, AsyncSessionLocal
from routers import auth, employees, attendance, salary, reports, settings as settings_router, notifications as notifications_router, working_days as working_days_router

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
            # Azure Face API — store person_id per employee
            await _session.execute(_text("""
                ALTER TABLE employees
                    ADD COLUMN IF NOT EXISTS azure_person_id TEXT
            """))
            await _session.commit()
        logger.info("✅ DB migration complete")
    except Exception as _e:
        logger.warning(f"⚠️ DB migration warning: {_e}")

    # Verify Azure Face API credentials at startup
    try:
        from core.azure_face_service import AZURE_ENDPOINT, AZURE_KEY
        if AZURE_ENDPOINT and AZURE_KEY:
            logger.info("✅ Azure Face API configured")
        else:
            logger.warning("⚠️ AZURE_FACE_ENDPOINT or AZURE_FACE_KEY not set")
    except Exception as e:
        logger.warning(f"⚠️ Azure Face API check failed: {e}")
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