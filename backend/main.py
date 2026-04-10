"""
MIND FORGE — AI Assisted Learning Platform
FastAPI application entry point
"""

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from contextlib import asynccontextmanager
import logging

from app.core.config import settings
from app.core.database import engine, Base
from app.core.redis_client import redis_manager
from app.websockets.manager import ws_manager
from app.routers import auth, teacher, student, parent, admin
import app.models  # noqa: F401 — registers all models with Base

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown lifecycle handler."""
    logger.info("Starting MIND FORGE backend...")
    import subprocess, sys, os
    from sqlalchemy import text
    backend_dir = os.path.dirname(os.path.abspath(__file__))

    # Pre-flight: if DB has tables but no Alembic history (e.g. was bootstrapped
    # by create_all on a previous deployment), stamp to head so Alembic doesn't
    # try to replay every migration on an already-populated database.
    try:
        async with engine.connect() as _conn:
            alembic_tracked = await _conn.scalar(text(
                "SELECT COUNT(*) FROM alembic_version"
            ))
    except Exception:
        alembic_tracked = 0  # table doesn't exist yet

    if not alembic_tracked:
        try:
            async with engine.connect() as _conn:
                users_exist = await _conn.scalar(text(
                    "SELECT EXISTS (SELECT 1 FROM information_schema.tables "
                    "WHERE table_schema = 'public' AND table_name = 'users')"
                ))
        except Exception:
            users_exist = False

        if users_exist:
            logger.info("DB has tables but no Alembic history — stamping to head.")
            stamp = subprocess.run(
                [sys.executable, "-m", "alembic", "stamp", "head"],
                capture_output=True, text=True, cwd=backend_dir,
            )
            logger.info(f"Alembic stamp: {stamp.stdout.strip()}")
            if stamp.returncode != 0:
                logger.warning(f"Alembic stamp warning: {stamp.stderr.strip()}")

    # Run Alembic migrations to apply any pending schema changes
    result = subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        capture_output=True, text=True, cwd=backend_dir,
    )
    logger.info(f"Alembic: {result.stdout.strip()}")
    if result.returncode != 0:
        logger.error(f"Alembic migration failed: {result.stderr.strip()}")
    else:
        logger.info("Alembic migrations applied.")
    # Create any tables not covered by migrations (idempotent)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    logger.info("Database tables ready.")
    # Seed default admin if not exists
    from sqlalchemy.ext.asyncio import AsyncSession
    from sqlalchemy import select, text
    from app.models.user import User, UserRole
    import bcrypt
    async with AsyncSession(engine) as session:
        result = await session.execute(
            select(User).where(User.username == "admin", User.deleted_at.is_(None))
        )
        if not result.scalar_one_or_none():
            hashed = bcrypt.hashpw(b"123456", bcrypt.gensalt(12)).decode()
            admin_user = User(
                username="admin", mpin_hash=hashed,
                role=UserRole.admin, is_active=True, is_approved=True,
            )
            session.add(admin_user)
            await session.commit()
            logger.info("Default admin seeded (username=admin, mpin=123456)")
    # Initialize Redis connection
    await redis_manager.connect()
    # Start Redis subscriber in background
    import asyncio
    asyncio.create_task(redis_manager.start_subscriber(ws_manager))
    logger.info("MIND FORGE backend is ready.")
    yield
    logger.info("Shutting down MIND FORGE backend...")
    await redis_manager.disconnect()


app = FastAPI(
    title="MIND FORGE API",
    description="AI Assisted Learning Platform — Backend API",
    version="1.0.0",
    lifespan=lifespan,
)

# ─── CORS ─────────────────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.BACKEND_CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─── Routers ──────────────────────────────────────────────────────────────────
app.include_router(auth.router, prefix="/api/auth", tags=["Authentication"])
app.include_router(teacher.router, prefix="/api/teacher", tags=["Teacher"])
app.include_router(student.router, prefix="/api/student", tags=["Student"])
app.include_router(parent.router, prefix="/api/parent", tags=["Parent"])
app.include_router(admin.router, prefix="/api/admin", tags=["Admin"])


# ─── WebSocket endpoint ───────────────────────────────────────────────────────
@app.websocket("/ws/{user_id}")
async def websocket_endpoint(websocket: WebSocket, user_id: int):
    """
    WebSocket endpoint for real-time events.
    Client connects with their user_id; the server fans out
    events (attendance updates, grade updates, new test published, etc.)
    using Redis pub/sub across multiple backend instances.
    """
    await ws_manager.connect(websocket, user_id)
    try:
        while True:
            # Keep connection alive; receive any client-side pings
            data = await websocket.receive_text()
            if data == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        await ws_manager.disconnect(websocket, user_id)


# ─── Health check ─────────────────────────────────────────────────────────────
@app.get("/api/health", tags=["Health"])
async def health_check():
    return {"status": "ok", "app": "MIND FORGE"}


# ─── Media proxy ──────────────────────────────────────────────────────────────
@app.get("/api/media/{bucket}/{key:path}", tags=["Media"])
async def serve_media(bucket: str, key: str):
    """
    Proxy a file from MinIO through the backend.
    Used for profile pictures so URLs never contain internal MinIO hostnames.
    Only allows the profiles bucket to prevent arbitrary bucket access.
    """
    from app.services import storage_service
    from minio.error import S3Error

    ALLOWED_BUCKETS = {settings.MINIO_BUCKET_PROFILES}
    if bucket not in ALLOWED_BUCKETS:
        raise HTTPException(status_code=403, detail="Access denied")

    try:
        client = storage_service._get_client()
        response = client.get_object(bucket, key)
        content_type = response.headers.get("content-type", "image/jpeg")
        return StreamingResponse(response, media_type=content_type)
    except S3Error as e:
        raise HTTPException(status_code=404, detail="File not found")
