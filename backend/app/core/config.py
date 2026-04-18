"""
Application configuration via Pydantic BaseSettings.
All values are loaded from environment variables / .env file.
"""

from typing import List, Union
from pydantic import AnyHttpUrl, field_validator
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
    APP_ENV: str = "development"
    DEBUG: bool = True

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
    JWT_SECRET: str = "change_me_super_secret_jwt_key_at_least_32_chars"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_MINUTES: int = 60           # 1 hour access token
    JWT_REFRESH_EXPIRE_DAYS: int = 30      # 30 day refresh token

    # ── Google Gemini AI ──────────────────────────────────────────────────────
    GEMINI_API_KEY: str = ""
    GEMINI_MODEL: str = "gemini-2.5-flash"

    # ── Groq AI ───────────────────────────────────────────────────────────────
    GROQ_API_KEY: str = ""
    GROQ_MODEL: str = "llama-3.3-70b-versatile"

    # ── CORS ──────────────────────────────────────────────────────────────────
    BACKEND_CORS_ORIGINS: List[str] = ["http://localhost", "http://localhost:80"]

    @field_validator("BACKEND_CORS_ORIGINS", mode="before")
    @classmethod
    def assemble_cors_origins(cls, v: Union[str, List[str]]) -> List[str]:
        if isinstance(v, str):
            import json
            try:
                return json.loads(v)
            except Exception:
                return [i.strip() for i in v.split(",")]
        return v


settings = Settings()
