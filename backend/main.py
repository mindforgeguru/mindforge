"""
MIND FORGE — AI Assisted Learning Platform
FastAPI application entry point
"""

from fastapi import (
    FastAPI, WebSocket, WebSocketDisconnect,
    HTTPException, Query, Request,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, Response
from starlette.middleware.base import BaseHTTPMiddleware
from contextlib import asynccontextmanager
import logging

from app.core.config import settings
from app.core.database import engine, Base
from app.core.redis_client import redis_manager
from app.websockets.manager import ws_manager
from app.routers import auth, teacher, student, parent, admin, xp
from app.routers import database_router, feedback
import app.models  # noqa: F401 — registers all models with Base

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ─── Sentry init ──────────────────────────────────────────────────────────────
# Must run before FastAPI() is created so the FastAPI integration can attach.
# Empty DSN (default in dev) skips init entirely.
if settings.SENTRY_DSN:
    import sentry_sdk
    from sentry_sdk.integrations.fastapi import FastApiIntegration
    from sentry_sdk.integrations.starlette import StarletteIntegration

    _SCRUB_KEYS = {
        "mpin", "password", "token", "refresh_token", "mpin_hash",
        "access_token", "authorization", "cookie",
    }

    def _scrub_event(event, hint):
        try:
            req = event.get("request") or {}
            for section in ("data", "headers", "cookies"):
                bucket = req.get(section)
                if isinstance(bucket, dict):
                    for k in list(bucket.keys()):
                        if k.lower() in _SCRUB_KEYS:
                            bucket[k] = "[scrubbed]"
        except Exception:
            pass
        return event

    sentry_sdk.init(
        dsn=settings.SENTRY_DSN,
        environment=settings.APP_ENV,
        integrations=[
            StarletteIntegration(transaction_style="endpoint"),
            FastApiIntegration(transaction_style="endpoint"),
        ],
        traces_sample_rate=settings.SENTRY_TRACES_SAMPLE_RATE,
        send_default_pii=False,
        before_send=_scrub_event,
    )
    logger.info(f"Sentry initialized (env={settings.APP_ENV})")


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
        stderr = result.stderr.strip()
        # Ignore race condition: another worker process already applied the migration
        if "Online migration expected to match one row" in stderr:
            logger.info("Alembic: migration already applied by another worker, continuing.")
        else:
            logger.error(f"Alembic migration failed: {stderr}")
    else:
        logger.info("Alembic migrations applied.")
    # Create any tables not covered by migrations (idempotent)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    logger.info("Database tables ready.")
    # Seed default admin if not exists. MPIN is read from ADMIN_SEED_MPIN to
    # avoid shipping a known-default credential to production. If the env var
    # is missing or malformed the seed is skipped — surfaces as a clear log
    # warning instead of silently provisioning a weak account.
    from sqlalchemy.ext.asyncio import AsyncSession
    from sqlalchemy import select, text
    from app.models.user import User, UserRole
    import bcrypt
    seed_mpin = os.environ.get("ADMIN_SEED_MPIN", "").strip()
    if not (seed_mpin.isdigit() and len(seed_mpin) == 6):
        logger.warning(
            "ADMIN_SEED_MPIN not set or not a 6-digit numeric string — "
            "skipping admin seed. Set ADMIN_SEED_MPIN in env to provision."
        )
    else:
        async with AsyncSession(engine) as session:
            result = await session.execute(
                select(User).where(User.username == "admin", User.deleted_at.is_(None))
            )
            if not result.scalar_one_or_none():
                hashed = bcrypt.hashpw(seed_mpin.encode(), bcrypt.gensalt(12)).decode()
                admin_user = User(
                    username="admin", mpin_hash=hashed,
                    role=UserRole.admin, is_active=True, is_approved=True,
                )
                session.add(admin_user)
                await session.commit()
                logger.info("Default admin seeded (username=admin) with ADMIN_SEED_MPIN")
    # Initialize Redis connection
    await redis_manager.connect()
    # Start Redis subscriber in background
    import asyncio
    asyncio.create_task(redis_manager.start_subscriber(ws_manager))
    logger.info("MIND FORGE backend is ready.")
    yield
    logger.info("Shutting down MIND FORGE backend...")
    await redis_manager.disconnect()


# API docs (Swagger UI + ReDoc + openapi.json) are an information-disclosure
# surface — they enumerate every endpoint, parameter, and role. Expose them
# only when APP_ENV is explicitly set to "development".
_dev_mode = settings.APP_ENV == "development"

app = FastAPI(
    title="MIND FORGE API",
    description="AI Assisted Learning Platform — Backend API",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs" if _dev_mode else None,
    redoc_url="/redoc" if _dev_mode else None,
    openapi_url="/openapi.json" if _dev_mode else None,
)

# ─── Security headers ─────────────────────────────────────────────────────────

class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Adds security headers to every response."""
    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)
        response.headers["Strict-Transport-Security"] = (
            "max-age=31536000; includeSubDomains"
        )
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Content-Security-Policy"] = "default-src 'none'"
        return response


# ─── CORS ─────────────────────────────────────────────────────────────────────
# CORS must be added before SecurityHeadersMiddleware so that preflight OPTIONS
# responses also carry the security headers.
app.add_middleware(SecurityHeadersMiddleware)
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
app.include_router(database_router.router, prefix="/api/teacher/database", tags=["Teacher Database"])
app.include_router(xp.router, prefix="/api/xp", tags=["XP"])
app.include_router(feedback.router, prefix="/api/feedback", tags=["Feedback"])


# ─── WebSocket endpoint ───────────────────────────────────────────────────────
@app.websocket("/ws/{user_id}")
async def websocket_endpoint(
    websocket: WebSocket,
    user_id: int,
    token: str = Query(...),
):
    """
    WebSocket endpoint for real-time events.

    Authentication: the client MUST pass its current access token as a
    `?token=` query string. We validate the JWT, confirm the `sub` claim
    matches the URL user_id (preventing cross-user subscription), and
    reject revoked tokens (logout/account-delete blacklists the JTI).
    Cookies/headers can't be set on WebSocket handshakes in browsers,
    so query string is the standard place for the token.
    """
    from app.core.security import decode_access_token
    from jose import JWTError

    # 1008 = Policy Violation. Closing here means handshake never completes.
    POLICY_VIOLATION = 1008

    try:
        payload = decode_access_token(token)
    except JWTError:
        await websocket.close(code=POLICY_VIOLATION)
        return

    if payload.get("type") == "refresh":
        await websocket.close(code=POLICY_VIOLATION)
        return

    try:
        token_user_id = int(payload.get("sub", -1))
    except (TypeError, ValueError):
        await websocket.close(code=POLICY_VIOLATION)
        return

    if token_user_id != user_id:
        await websocket.close(code=POLICY_VIOLATION)
        return

    jti = payload.get("jti")
    if jti and await redis_manager.is_access_jti_revoked(jti):
        await websocket.close(code=POLICY_VIOLATION)
        return

    await ws_manager.connect(websocket, user_id)
    try:
        while True:
            # Keep connection alive; receive any client-side pings
            data = await websocket.receive_text()
            if data == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        pass
    except Exception as e:
        logger.warning(f"WebSocket error for user {user_id}: {e}")
    finally:
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
    except S3Error:
        raise HTTPException(status_code=404, detail="File not found")
