"""
main.py — Garage Attendance System API
FastAPI + Neon PostgreSQL + ArcFace + MediaPipe
"""
import os
# Must be set before TensorFlow/Keras is imported anywhere.
os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from dotenv import load_dotenv

import asyncio

from core.database import ping_db, AsyncSessionLocal
from core.face_service import warmup_models
from core import face_cache
from routers import auth, employees, attendance, salary, reports, settings as settings_router

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

    # Preload face recognition models so first request is fast
    logger.info("🔄 Warming up face recognition models…")
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(None, warmup_models)
    logger.info("✅ Face models ready")

    # Load all face vectors into memory — scan will use cache, not DB
    logger.info("🔄 Loading face vectors into memory cache…")
    try:
        from sqlalchemy import text as sa_text
        import json
        async with AsyncSessionLocal() as session:
            result = await session.execute(sa_text(
                "SELECT fv.employee_id, e.company_id, e.name, "
                "fv.face_vector::text AS face_vector "
                "FROM face_vectors fv "
                "JOIN employees e ON e.id = fv.employee_id "
                "WHERE e.status = 'active'"
            ))
            rows = result.fetchall()
            parsed = [
                (r[0], r[1], r[2], json.loads(r[3]))
                for r in rows
            ]
        await loop.run_in_executor(None, face_cache.load_all, parsed)
    except Exception as e:
        logger.warning(f"⚠️ Face cache load failed (will use DB fallback): {e}")
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