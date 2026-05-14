"""
Seed users that the Flutter integration tests expect to find in the local DB.

Creates / updates (idempotent — safe to re-run):
  - admin          (mpin 300573)  — already auto-seeded if ADMIN_SEED_MPIN is set,
                                    but this script also ensures it's approved.
  - chinmay_sir    (mpin 100898, role=teacher)
  - dummy8         (mpin 111111,  role=student, grade 8, parent=dummy8_dad)
  - dummy8_dad     (mpin 111111,  role=parent)

Defaults match `frontend/integration_test/all_screens_test.dart`. Override via
env vars (e.g. STUDENT_USER=...) if your integration_test build uses
different --dart-define values.

Run from the backend directory with the local stack up:
    cd backend
    python3 scripts/seed_integration_test_users.py

Exits 0 on success. Non-destructive: existing users are left alone except for
ensuring is_approved=True and re-hashing the MPIN to the value above.
"""

import asyncio
import os
import sys

# Allow running as `python3 scripts/seed_integration_test_users.py`
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import engine
from app.core.security import hash_mpin
from app.models.user import User, UserRole, StudentProfile, TeacherProfile


# ── Configurable via env vars; defaults mirror integration_test/* ─────────────
USERS = {
    "admin":       {"mpin": os.environ.get("ADMIN_MPIN", "300573"),    "role": UserRole.admin},
    "chinmay_sir": {"mpin": os.environ.get("TEACHER_MPIN", "100898"),  "role": UserRole.teacher},
    "dummy8":      {"mpin": os.environ.get("STUDENT_MPIN", "111111"),  "role": UserRole.student,
                    "grade": 8, "parent": "dummy8_dad"},
    "dummy8_dad":  {"mpin": os.environ.get("PARENT_MPIN", "111111"),   "role": UserRole.parent},
}


async def _upsert_user(session: AsyncSession, username: str, spec: dict) -> User:
    result = await session.execute(
        select(User).where(User.username == username, User.deleted_at.is_(None))
    )
    user = result.scalar_one_or_none()

    if user is None:
        user = User(
            username=username,
            mpin_hash=hash_mpin(spec["mpin"]),
            role=spec["role"],
            is_active=True,
            is_approved=True,
        )
        session.add(user)
        await session.flush()  # populate user.id
        print(f"  CREATED {username} (id={user.id}, role={spec['role'].value})")
    else:
        user.mpin_hash = hash_mpin(spec["mpin"])
        user.is_active = True
        user.is_approved = True
        print(f"  UPDATED {username} (id={user.id}, role={user.role.value}) — reset MPIN + approved")

    return user


async def _ensure_teacher_profile(session: AsyncSession, user: User) -> None:
    result = await session.execute(
        select(TeacherProfile).where(TeacherProfile.user_id == user.id)
    )
    if result.scalar_one_or_none() is None:
        session.add(TeacherProfile(
            user_id=user.id,
            teachable_subjects=["Mathematics", "Physics"],
        ))
        print(f"    + teacher profile")


async def _ensure_student_profile(
    session: AsyncSession, user: User, grade: int, parent_user_id: int | None
) -> None:
    result = await session.execute(
        select(StudentProfile).where(StudentProfile.user_id == user.id)
    )
    profile = result.scalar_one_or_none()
    if profile is None:
        session.add(StudentProfile(
            user_id=user.id,
            grade=grade,
            parent_user_id=parent_user_id,
            additional_subjects=[],
        ))
        print(f"    + student profile (grade {grade}, parent_id={parent_user_id})")
    else:
        # keep parent link fresh in case parent was re-created
        if parent_user_id and profile.parent_user_id != parent_user_id:
            profile.parent_user_id = parent_user_id
            print(f"    ~ student profile parent link → {parent_user_id}")


async def main() -> int:
    print("Seeding integration-test users...")
    async with AsyncSession(engine) as session:
        # Pass 1 — upsert all base users. Need parent before student so the
        # student can reference parent_user_id.
        created: dict[str, User] = {}
        for username in ["admin", "chinmay_sir", "dummy8_dad", "dummy8"]:
            spec = USERS[username]
            created[username] = await _upsert_user(session, username, spec)

        # Pass 2 — profiles
        await _ensure_teacher_profile(session, created["chinmay_sir"])
        await _ensure_student_profile(
            session, created["dummy8"],
            grade=USERS["dummy8"]["grade"],
            parent_user_id=created["dummy8_dad"].id,
        )

        await session.commit()

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
