"""
Application configuration via Pydantic BaseSettings.
All values are loaded from environment variables / .env file.
"""

from typing import List, Union
from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )

    # ── App ──────────────────────────────────────────────────────────────────
    APP_NAME: str = "MIND FORGE"
    # Secure default: production hides API docs (/docs, /openapi.json) and
    # any other dev-only surfaces. Local dev opts in via .env.local /
    # docker-compose.local.yml setting APP_ENV=development.
    APP_ENV: str = "production"
    DEBUG: bool = False

    # ── Database ─────────────────────────────────────────────────────────────
    DB_URL: str = "postgresql+asyncpg://mindforge:mindforge_secret@localhost:5432/mindforge"

    # ── Redis ─────────────────────────────────────────────────────────────────
    REDIS_URL: str = "redis://:redis_secret@localhost:6379/0"

    # ── MinIO ─────────────────────────────────────────────────────────────────
    MINIO_ENDPOINT: str = "localhost:9000"
    MINIO_ACCESS_KEY: str = "minioadmin"
    MINIO_SECRET_KEY: str = "minio_secret"
    MINIO_BUCKET_TESTS: str = "mindforge-tests"
    MINIO_BUCKET_PROFILES: str = "mindforge-profiles"
    MINIO_BUCKET_PDFS: str = "mindforge-pdfs"
    MINIO_BUCKET_DATABASE: str = "mindforge-database"  # old papers + chapters
    MINIO_USE_SSL: bool = False
    # Public base URL of the backend itself — used to build media proxy URLs
    # e.g. https://api.mindforge.guru  (no trailing slash)
    BACKEND_PUBLIC_URL: str = "https://api.mindforge.guru"

    # ── JWT ───────────────────────────────────────────────────────────────────
    # Required: no default. Generate with: python -c "import secrets; print(secrets.token_urlsafe(64))"
    # App refuses to start if unset — never run with a hardcoded fallback secret.
    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_MINUTES: int = 60           # 1 hour access token
    JWT_REFRESH_EXPIRE_DAYS: int = 30      # 30 day refresh token

    # ── Anthropic Claude AI ───────────────────────────────────────────────────
    # Primary provider for test + presentation generation. Falls back to
    # Gemini, then Groq, if unset or if a call fails.
    ANTHROPIC_API_KEY: str = ""
    ANTHROPIC_MODEL: str = "claude-opus-4-8"

    # ── Google Gemini AI ──────────────────────────────────────────────────────
    GEMINI_API_KEY: str = ""
    GEMINI_MODEL: str = "gemini-2.5-flash"

    # ── Groq AI ───────────────────────────────────────────────────────────────
    GROQ_API_KEY: str = ""
    GROQ_MODEL: str = "llama-3.3-70b-versatile"

    # ── Firebase Admin (push notifications) ──────────────────────────────────
    # Paste the full service-account JSON as a single-line string in Railway.
    # Leave empty to disable push notifications without breaking the app.
    FIREBASE_CREDENTIALS_JSON: str = ""

    # ── Sentry error tracking ────────────────────────────────────────────────
    # Empty DSN = Sentry disabled (intended for local dev). Set the DSN in
    # production env vars to start shipping errors + traces.
    SENTRY_DSN: str = ""
    SENTRY_TRACES_SAMPLE_RATE: float = 0.1

    # ── CORS ──────────────────────────────────────────────────────────────────
    BACKEND_CORS_ORIGINS: List[str] = [
        "http://localhost", "http://localhost:80",
        # Flutter `flutter run -d chrome --web-port=5001` dev server
        "http://localhost:5001", "http://127.0.0.1:5001",
        # Default dart2js port some IDE flows use
        "http://localhost:8080", "http://127.0.0.1:8080",
        "https://mindforge.guru", "https://www.mindforge.guru",
    ]

    @field_validator("BACKEND_CORS_ORIGINS", mode="before")
    @classmethod
    def assemble_cors_origins(cls, v: Union[str, List[str]]) -> List[str]:
        if isinstance(v, str):
            import json
            try:
                origins = json.loads(v)
            except Exception:
                origins = [i.strip() for i in v.split(",")]
        else:
            origins = v
        # The app runs CORSMiddleware with allow_credentials=True. A wildcard
        # origin in that mode makes Starlette reflect ANY origin with
        # Access-Control-Allow-Credentials: true — the classic dangerous
        # misconfiguration. Refuse to start rather than ship it; list explicit
        # origins instead.
        if any(str(o).strip() == "*" for o in (origins or [])):
            raise ValueError(
                "BACKEND_CORS_ORIGINS must not contain '*' — credentialed CORS "
                "requires an explicit origin allowlist."
            )
        return origins

    @model_validator(mode="after")
    def _reject_insecure_production_defaults(self):
        """Fail fast if a production deploy is still using the built-in default
        credentials. These defaults exist only for local dev (APP_ENV set to
        something other than 'production'); shipping them to prod would leave
        the object store / datastores reachable with publicly-known secrets.
        Same philosophy as JWT_SECRET having no default at all."""
        if self.APP_ENV != "production":
            return self

        insecure: List[str] = []
        if self.MINIO_ACCESS_KEY == "minioadmin":
            insecure.append("MINIO_ACCESS_KEY")
        if self.MINIO_SECRET_KEY == "minio_secret":
            insecure.append("MINIO_SECRET_KEY")
        if "mindforge_secret" in self.DB_URL:
            insecure.append("DB_URL (default password)")
        if "redis_secret" in self.REDIS_URL:
            insecure.append("REDIS_URL (default password)")

        if insecure:
            raise ValueError(
                "Refusing to start in production (APP_ENV=production) with "
                "default credentials still set: " + ", ".join(insecure) + ". "
                "Set strong values in the environment, or set APP_ENV to a "
                "non-production value for local development."
            )
        return self


settings = Settings()
