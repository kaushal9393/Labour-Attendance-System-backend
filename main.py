"""
main.py — Garage Attendance System API
FastAPI + Neon PostgreSQL + ArcFace + MediaPipe
"""
import os
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

import asyncio

from core.database import ping_db
from core.face_service import warmup_models
from routers import auth, employees, attendance, salary, reports, settings as settings_router

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("garage_api")

_models_ready = False


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _models_ready
    # ── Startup ──
    logger.info("Starting Garage Attendance API…")
    db_ok = await ping_db()
    if db_ok:
        logger.info("✅ Database connected")
    else:
        logger.warning("⚠️  Database connection failed — check DATABASE_URL")

    # Warmup AI models in a thread (CPU-bound, must not block event loop)
    loop = asyncio.get_event_loop()
    try:
        _models_ready = await loop.run_in_executor(None, warmup_models)
    except Exception as exc:
        logger.warning(f"⚠️  Model warmup error: {exc}")

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

# ── CORS ──────────────────────────────────────────────────────
origins = os.getenv("CORS_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routers ───────────────────────────────────────────────────
app.include_router(auth.router)
app.include_router(employees.router)
app.include_router(attendance.router)
app.include_router(salary.router)
app.include_router(reports.router)
app.include_router(settings_router.router)


# ── Health check ──────────────────────────────────────────────
@app.get("/health", tags=["Health"])
async def health():
    return {"status": "ok", "service": "Garage Attendance API", "model_ready": _models_ready}


@app.get("/", tags=["Health"])
async def root():
    return {"message": "Garage Attendance System API v1.0 — /docs for Swagger UI"}
