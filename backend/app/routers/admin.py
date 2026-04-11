"""
Admin router — all endpoints require admin role.
"""

from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from sqlalchemy import func as sqlfunc

from app.core.database import get_db
from app.core.redis_client import redis_manager
from app.core.security import get_current_admin
from app.models.academic_year import AcademicYear
from app.models.fees import FeePayment, FeeStructure, PaymentInfo
from app.models.timetable import TimetableConfig, TimetableSlot
from app.models.user import User, UserRole, StudentProfile, TeacherProfile
from app.schemas.fees import (
    FeePaymentCreate, FeePaymentResponse, FeePaymentUpdate,
    FeeStructureCreate, FeeStructureResponse, FeeStructureUpdate,
    PaymentInfoCreate, PaymentInfoResponse,
)
from app.schemas.timetable import TimetableConfigCreate, TimetableConfigResponse
from app.schemas.user import AdminMpinUpdate, AdminUserEdit, UserResponse, UserUpdate, UserWithProfileResponse
from app.services import storage_service
from app.services import pdf_service
from fastapi.responses import Response

router = APIRouter()


# ─── Admin Profile ────────────────────────────────────────────────────────────

@router.get("/profile", response_model=UserResponse)
async def get_admin_profile(
    current_admin: User = Depends(get_current_admin),
):
    """Return the current admin's profile."""
    return current_admin


@router.post("/profile/photo", status_code=status.HTTP_200_OK)
async def upload_admin_photo(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Upload or replace the admin's profile picture."""
    file_bytes = await file.read()
    ext = file.filename.rsplit(".", 1)[-1].lower() if file.filename else "jpg"
    bucket = "mindforge-profiles"
    key = f"profiles/admin/{current_admin.id}/avatar.{ext}"
    await storage_service.upload_file(bucket, key, file_bytes)
    public_url = storage_service.get_public_url(bucket, key)

    result = await db.execute(select(User).where(User.id == current_admin.id))
    admin_user = result.scalar_one()
    admin_user.profile_pic_url = public_url
    await db.commit()
    return {"profile_pic_url": public_url}


@router.put("/profile/username", status_code=status.HTTP_200_OK)
async def change_admin_username(
    payload: dict,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Change the admin's own username."""
    new_username = (payload.get("username") or "").strip()
    if not new_username or len(new_username) < 3:
        raise HTTPException(status_code=400, detail="Username must be at least 3 characters.")
    conflict = await db.execute(
        select(User).where(User.username == new_username, User.id != current_admin.id, User.deleted_at.is_(None))
    )
    if conflict.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Username already taken.")
    result = await db.execute(select(User).where(User.id == current_admin.id))
    admin_user = result.scalar_one()
    admin_user.username = new_username
    await db.commit()
    return {"username": new_username}


@router.put("/profile/mpin", status_code=status.HTTP_200_OK)
async def change_admin_mpin(
    payload: AdminMpinUpdate,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Change the admin's MPIN after verifying the current one."""
    from app.core.security import hash_mpin, verify_mpin
    if not verify_mpin(payload.current_mpin, current_admin.mpin_hash):
        raise HTTPException(status_code=400, detail="Current MPIN is incorrect.")
    result = await db.execute(select(User).where(User.id == current_admin.id))
    admin_user = result.scalar_one()
    admin_user.mpin_hash = hash_mpin(payload.new_mpin)
    await db.commit()
    return {"message": "MPIN updated successfully."}


# ─── User Management ──────────────────────────────────────────────────────────

@router.get("/users/pending", response_model=List[UserResponse])
async def get_pending_users(
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """List all users awaiting approval."""
    result = await db.execute(
        select(User).where(User.is_approved == False, User.deleted_at.is_(None))
        .order_by(User.created_at.asc())
    )
    return result.scalars().all()


@router.get("/users", response_model=List[UserWithProfileResponse])
async def get_all_users(
    role: Optional[str] = Query(None),
    grade: Optional[int] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """List all active, approved users. Optionally filter by role and grade."""
    base_query = (
        select(User, StudentProfile)
        .outerjoin(StudentProfile, StudentProfile.user_id == User.id)
        .where(User.deleted_at.is_(None), User.is_approved == True)
    )
    if role:
        base_query = base_query.where(User.role == role)

    # Grade filter: for students → direct grade match;
    # for parents → find parents whose linked child is in that grade.
    if grade is not None:
        if role == "parent":
            child_ids_q = (
                select(StudentProfile.parent_user_id)
                .join(User, User.id == StudentProfile.user_id)
                .where(StudentProfile.grade == grade, User.deleted_at.is_(None))
            )
            base_query = base_query.where(User.id.in_(child_ids_q))
        else:
            base_query = base_query.where(StudentProfile.grade == grade)

    result = await db.execute(base_query.order_by(User.created_at.desc()))
    rows = result.all()

    # Batch-fetch parent usernames
    parent_ids = {
        profile.parent_user_id
        for user, profile in rows
        if profile and profile.parent_user_id
    }
    parent_username_map: dict[int, str] = {}
    if parent_ids:
        pu_result = await db.execute(select(User).where(User.id.in_(parent_ids)))
        for pu in pu_result.scalars().all():
            parent_username_map[pu.id] = pu.username

    # Batch-fetch linked student usernames for parent rows
    parent_user_ids_in_result = {user.id for user, _ in rows if user.role == UserRole.parent}
    student_username_map: dict[int, str] = {}
    if parent_user_ids_in_result:
        linked_students_result = await db.execute(
            select(User, StudentProfile)
            .join(StudentProfile, StudentProfile.user_id == User.id)
            .where(StudentProfile.parent_user_id.in_(parent_user_ids_in_result), User.deleted_at.is_(None))
        )
        for su, sp in linked_students_result.all():
            student_username_map[sp.parent_user_id] = su.username

    # Batch-fetch teacher profiles for subjects
    teacher_ids = {user.id for user, _ in rows if user.role == UserRole.teacher}
    teacher_subjects_map: dict[int, list] = {}
    if teacher_ids:
        tp_result = await db.execute(
            select(TeacherProfile).where(TeacherProfile.user_id.in_(teacher_ids))
        )
        for tp in tp_result.scalars().all():
            teacher_subjects_map[tp.user_id] = tp.teachable_subjects or []

    return [
        UserWithProfileResponse(
            id=user.id,
            username=user.username,
            role=user.role,
            is_active=user.is_active,
            is_approved=user.is_approved,
            created_at=user.created_at,
            deleted_at=user.deleted_at,
            phone=user.phone,
            email=user.email,
            grade=profile.grade if profile else None,
            parent_user_id=profile.parent_user_id if profile else None,
            parent_username=parent_username_map.get(profile.parent_user_id) if profile and profile.parent_user_id else None,
            student_username=student_username_map.get(user.id) if user.role == UserRole.parent else None,
            teachable_subjects=teacher_subjects_map.get(user.id) if user.role == UserRole.teacher else None,
            additional_subjects=profile.additional_subjects if profile else None,
        )
        for user, profile in rows
    ]


@router.put("/users/{user_id}", response_model=UserWithProfileResponse)
async def edit_user(
    user_id: int,
    payload: AdminUserEdit,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Edit a user's username, role, grade (students), or reset their MPIN."""
    result = await db.execute(
        select(User).where(User.id == user_id, User.deleted_at.is_(None))
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")
    if user.role == UserRole.admin:
        raise HTTPException(status_code=403, detail="Cannot modify admin account.")

    # Update phone
    if payload.phone is not None:
        new_phone = payload.phone.strip() or None
        if new_phone and new_phone != user.phone:
            conflict = await db.execute(
                select(User).where(
                    User.phone == new_phone,
                    User.deleted_at.is_(None),
                    User.id != user_id,
                )
            )
            if conflict.scalar_one_or_none():
                raise HTTPException(status_code=409, detail="An account with this phone number already exists.")
        user.phone = new_phone

    # Update email
    if payload.email is not None:
        user.email = payload.email.strip() or None

    # Update username
    if payload.username and payload.username != user.username:
        conflict = await db.execute(
            select(User).where(
                User.username == payload.username,
                User.deleted_at.is_(None),
                User.id != user_id,
            )
        )
        if conflict.scalar_one_or_none():
            raise HTTPException(status_code=409, detail="Username already taken.")
        user.username = payload.username

    # Reset MPIN
    if payload.new_mpin:
        from app.core.security import hash_mpin
        user.mpin_hash = hash_mpin(payload.new_mpin)

    # Handle role change — migrate profiles as needed
    old_role = user.role
    new_role = payload.role if payload.role and payload.role != old_role else None

    if new_role and new_role == UserRole.admin:
        raise HTTPException(status_code=403, detail="Cannot promote a user to admin.")

    if new_role:
        # Remove old profile
        if old_role == UserRole.student:
            old_profile = await db.execute(
                select(StudentProfile).where(StudentProfile.user_id == user_id)
            )
            sp = old_profile.scalar_one_or_none()
            if sp:
                await db.delete(sp)
        elif old_role == UserRole.teacher:
            old_tp = await db.execute(
                select(TeacherProfile).where(TeacherProfile.user_id == user_id)
            )
            tp = old_tp.scalar_one_or_none()
            if tp:
                await db.delete(tp)

        user.role = new_role

        # Create new profile
        if new_role == UserRole.student:
            grade = payload.grade if payload.grade in (8, 9, 10) else 8
            db.add(StudentProfile(user_id=user_id, grade=grade))
        elif new_role == UserRole.teacher:
            db.add(TeacherProfile(user_id=user_id, teachable_subjects=[]))

    else:
        # No role change — update grade and/or parent_username if student
        if user.role == UserRole.student:
            profile_result = await db.execute(
                select(StudentProfile).where(StudentProfile.user_id == user_id)
            )
            sp = profile_result.scalar_one_or_none()
            if sp:
                if payload.grade is not None:
                    sp.grade = payload.grade
                if payload.additional_subjects is not None:
                    sp.additional_subjects = payload.additional_subjects
                if payload.parent_username is not None:
                    if payload.parent_username.strip() == "":
                        sp.parent_user_id = None
                    else:
                        from sqlalchemy import func as sa_func
                        parent_res = await db.execute(
                            select(User).where(
                                sa_func.lower(User.username) == payload.parent_username.strip().lower(),
                                User.role == UserRole.parent,
                                User.deleted_at.is_(None),
                            )
                        )
                        parent = parent_res.scalar_one_or_none()
                        if not parent:
                            raise HTTPException(
                                status_code=404,
                                detail=f"No parent account found with username '{payload.parent_username.strip()}'.",
                            )
                        sp.parent_user_id = parent.id

        # No role change — update student_username link if parent
        elif user.role == UserRole.parent and payload.student_username is not None:
            from sqlalchemy import func as sa_func
            if payload.student_username.strip() == "":
                # Unlink: clear parent_user_id on any student linked to this parent
                linked_res = await db.execute(
                    select(StudentProfile).where(StudentProfile.parent_user_id == user_id)
                )
                for sp in linked_res.scalars().all():
                    sp.parent_user_id = None
            else:
                # Find the student by username and set their parent_user_id
                student_user_res = await db.execute(
                    select(User).where(
                        sa_func.lower(User.username) == payload.student_username.strip().lower(),
                        User.role == UserRole.student,
                        User.deleted_at.is_(None),
                    )
                )
                student_user = student_user_res.scalar_one_or_none()
                if not student_user:
                    raise HTTPException(
                        status_code=404,
                        detail=f"No student account found with username '{payload.student_username.strip()}'.",
                    )
                student_profile_res = await db.execute(
                    select(StudentProfile).where(StudentProfile.user_id == student_user.id)
                )
                student_profile = student_profile_res.scalar_one_or_none()
                if student_profile:
                    student_profile.parent_user_id = user_id

        # No role change — update teachable_subjects if teacher
        elif user.role == UserRole.teacher and payload.teachable_subjects is not None:
            tp_result = await db.execute(
                select(TeacherProfile).where(TeacherProfile.user_id == user_id)
            )
            tp = tp_result.scalar_one_or_none()
            if tp:
                tp.teachable_subjects = payload.teachable_subjects

    await db.commit()
    await db.refresh(user)

    # Invalidate student profile cache if the edited user is/was a student
    if old_role == UserRole.student or user.role == UserRole.student:
        from app.core.cache import invalidate_student_profile
        await invalidate_student_profile(user_id)

    # Fetch final student profile + parent username for response
    final_profile = None
    parent_username = None
    student_username = None
    teachable_subjects = None

    if user.role == UserRole.student:
        pr = await db.execute(
            select(StudentProfile).where(StudentProfile.user_id == user_id)
        )
        final_profile = pr.scalar_one_or_none()
        if final_profile and final_profile.parent_user_id:
            pu = await db.execute(
                select(User).where(User.id == final_profile.parent_user_id)
            )
            parent_user = pu.scalar_one_or_none()
            if parent_user:
                parent_username = parent_user.username

    elif user.role == UserRole.parent:
        linked_student_res = await db.execute(
            select(User).join(StudentProfile, StudentProfile.user_id == User.id)
            .where(StudentProfile.parent_user_id == user_id, User.deleted_at.is_(None))
        )
        linked_student = linked_student_res.scalars().first()
        if linked_student:
            student_username = linked_student.username

    elif user.role == UserRole.teacher:
        tp_res = await db.execute(
            select(TeacherProfile).where(TeacherProfile.user_id == user_id)
        )
        tp = tp_res.scalar_one_or_none()
        if tp:
            teachable_subjects = tp.teachable_subjects or []

    # Notify the edited user so their app can refresh / prompt re-login
    await redis_manager.publish({
        "target_type": "user",
        "user_id": user.id,
        "payload": {
            "event": "profile_updated",
            "new_username": user.username,
            "message": "Your account has been updated by the admin.",
        },
    })

    return UserWithProfileResponse(
        id=user.id, username=user.username, role=user.role,
        is_active=user.is_active, is_approved=user.is_approved,
        created_at=user.created_at, deleted_at=user.deleted_at,
        phone=user.phone, email=user.email,
        grade=final_profile.grade if final_profile else None,
        parent_user_id=final_profile.parent_user_id if final_profile else None,
        parent_username=parent_username,
        student_username=student_username,
        teachable_subjects=teachable_subjects,
        additional_subjects=final_profile.additional_subjects if final_profile else None,
    )


@router.patch("/users/{user_id}/active", response_model=UserWithProfileResponse)
async def set_user_active(
    user_id: int,
    payload: UserUpdate,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Toggle a user's active status. Deactivating a student also deactivates their linked parent."""
    result = await db.execute(
        select(User).where(User.id == user_id, User.deleted_at.is_(None))
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")
    if user.role == UserRole.admin:
        raise HTTPException(status_code=403, detail="Cannot modify admin account status.")

    user.is_active = payload.is_active

    # Cascade: deactivating a student also deactivates their linked parent
    if user.role == UserRole.student and payload.is_active is False:
        profile_result = await db.execute(
            select(StudentProfile).where(StudentProfile.user_id == user_id)
        )
        profile = profile_result.scalar_one_or_none()
        if profile and profile.parent_user_id:
            parent_result = await db.execute(
                select(User).where(User.id == profile.parent_user_id, User.deleted_at.is_(None))
            )
            parent = parent_result.scalar_one_or_none()
            if parent:
                parent.is_active = False

    await db.commit()
    await db.refresh(user)

    profile_result2 = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == user_id)
    )
    profile2 = profile_result2.scalar_one_or_none()

    return UserWithProfileResponse(
        id=user.id,
        username=user.username,
        role=user.role,
        is_active=user.is_active,
        is_approved=user.is_approved,
        created_at=user.created_at,
        deleted_at=user.deleted_at,
        grade=profile2.grade if profile2 else None,
        parent_user_id=profile2.parent_user_id if profile2 else None,
    )


@router.post("/users/{user_id}/approve", response_model=UserResponse)
async def approve_user(
    user_id: int,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Approve a pending user account."""
    result = await db.execute(
        select(User).where(User.id == user_id, User.deleted_at.is_(None))
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")
    if user.is_approved:
        raise HTTPException(status_code=400, detail="User is already approved.")

    user.is_approved = True
    await db.commit()
    await db.refresh(user)

    # Notify the user that their account has been approved
    await redis_manager.publish({
        "target_type": "user",
        "user_id": user.id,
        "payload": {"event": "account_approved", "message": "Your account has been approved!"},
    })

    return user


@router.delete("/users/{user_id}/revoke", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_user(
    user_id: int,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """
    Soft-delete (revoke) a user account.
    Sets deleted_at timestamp and deactivates the account.
    """
    result = await db.execute(
        select(User).where(User.id == user_id, User.deleted_at.is_(None))
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")
    if user.role == UserRole.admin:
        raise HTTPException(status_code=403, detail="Cannot revoke an admin account.")

    user.soft_delete()
    await db.commit()

    # Notify the user (if connected) that their account has been revoked
    await redis_manager.publish({
        "target_type": "user",
        "user_id": user.id,
        "payload": {"event": "account_revoked", "message": "Your account access has been revoked."},
    })


# ─── Fee Summary (all students) ───────────────────────────────────────────────

@router.get("/fees/summary")
async def get_all_fee_summaries(
    academic_year: str = Query(...),
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Get fee summary for every student — total due, paid, and balance."""
    # Get all approved students with profiles
    students_result = await db.execute(
        select(User, StudentProfile)
        .join(StudentProfile, StudentProfile.user_id == User.id)
        .where(User.role == UserRole.student, User.deleted_at.is_(None), User.is_approved == True)
        .order_by(StudentProfile.grade, User.username)
    )
    rows = students_result.all()

    student_ids = [user.id for user, _ in rows]
    grades = {profile.grade for _, profile in rows}

    # Batch fetch: one query for all fee structures, one for all payments
    fs_result = await db.execute(
        select(FeeStructure).where(
            FeeStructure.academic_year == academic_year,
            FeeStructure.grade.in_(grades),
        )
    )
    fee_structures: dict[int, FeeStructure] = {fs.grade: fs for fs in fs_result.scalars().all()}

    payments_result = await db.execute(
        select(FeePayment)
        .where(FeePayment.student_id.in_(student_ids))
        .order_by(FeePayment.paid_at.desc())
    )
    all_payments = payments_result.scalars().all()
    payments_by_student: dict[int, list] = {}
    for p in all_payments:
        payments_by_student.setdefault(p.student_id, []).append(p)

    summaries = []
    for user, profile in rows:
        fs = fee_structures.get(profile.grade)
        if fs:
            total_fee = float(fs.base_amount)
            for subj in (profile.additional_subjects or []):
                if subj == "economics":
                    total_fee += float(fs.economics_fee)
                elif subj == "computer":
                    total_fee += float(fs.computer_fee)
                elif subj == "ai":
                    total_fee += float(fs.ai_fee)
        else:
            total_fee = 0.0

        payments = payments_by_student.get(user.id, [])
        total_paid = sum(float(p.amount) for p in payments)

        summaries.append({
            "student_id": user.id,
            "username": user.username,
            "grade": profile.grade,
            "academic_year": academic_year,
            "total_fee": total_fee,
            "total_paid": total_paid,
            "balance_due": max(0.0, total_fee - total_paid),
            "payments": [
                {
                    "id": p.id,
                    "amount": float(p.amount),
                    "paid_at": p.paid_at.isoformat(),
                    "notes": p.notes,
                }
                for p in payments
            ],
        })

    return summaries


# ─── Fee Structure ─────────────────────────────────────────────────────────────

@router.get("/fees/structure", response_model=List[FeeStructureResponse])
async def get_fee_structures(
    academic_year: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Get all fee structures, optionally filtered by academic year."""
    query = select(FeeStructure)
    if academic_year:
        query = query.where(FeeStructure.academic_year == academic_year)
    result = await db.execute(query.order_by(FeeStructure.academic_year, FeeStructure.grade))
    return result.scalars().all()


@router.post("/fees/structure", response_model=FeeStructureResponse, status_code=status.HTTP_201_CREATED)
async def create_fee_structure(
    payload: FeeStructureCreate,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Create a fee structure for a grade and academic year."""
    # Check for duplicate
    existing = await db.execute(
        select(FeeStructure).where(
            FeeStructure.grade == payload.grade,
            FeeStructure.academic_year == payload.academic_year,
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Fee structure for this grade/year already exists.")

    structure = FeeStructure(**payload.model_dump())
    db.add(structure)
    await db.commit()
    await db.refresh(structure)
    return structure


@router.put("/fees/structure/{structure_id}", response_model=FeeStructureResponse)
async def update_fee_structure(
    structure_id: int,
    payload: FeeStructureUpdate,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Update a fee structure."""
    result = await db.execute(select(FeeStructure).where(FeeStructure.id == structure_id))
    structure = result.scalar_one_or_none()
    if not structure:
        raise HTTPException(status_code=404, detail="Fee structure not found.")

    for field, value in payload.model_dump(exclude_none=True).items():
        setattr(structure, field, value)
    await db.commit()
    await db.refresh(structure)
    return structure


@router.delete("/fees/structure/{structure_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_fee_structure(
    structure_id: int,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Delete a fee structure by ID."""
    result = await db.execute(select(FeeStructure).where(FeeStructure.id == structure_id))
    structure = result.scalar_one_or_none()
    if not structure:
        raise HTTPException(status_code=404, detail="Fee structure not found.")
    await db.delete(structure)
    await db.commit()


@router.put("/fees/payments/{payment_id}", response_model=FeePaymentResponse)
async def update_fee_payment(
    payment_id: int,
    payload: FeePaymentUpdate,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Update the amount and/or notes of an existing fee payment."""
    result = await db.execute(select(FeePayment).where(FeePayment.id == payment_id))
    payment = result.scalar_one_or_none()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found.")
    payment.amount = payload.amount
    payment.notes = payload.notes
    payment.updated_by_admin_id = current_admin.id
    await db.commit()
    await db.refresh(payment)
    return payment


@router.delete("/fees/payments/{payment_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_fee_payment(
    payment_id: int,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Delete a fee payment entry."""
    result = await db.execute(select(FeePayment).where(FeePayment.id == payment_id))
    payment = result.scalar_one_or_none()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found.")
    await db.delete(payment)
    await db.commit()


@router.post("/fees/payments", response_model=FeePaymentResponse, status_code=status.HTTP_201_CREATED)
async def record_fee_payment(
    payload: FeePaymentCreate,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Record a fee payment for a student."""
    payment = FeePayment(
        student_id=payload.student_id,
        amount=payload.amount,
        notes=payload.notes,
        updated_by_admin_id=current_admin.id,
        **({"paid_at": payload.paid_at} if payload.paid_at else {}),
    )
    db.add(payment)
    await db.commit()
    await db.refresh(payment)

    # Notify parent if linked
    from app.models.user import StudentProfile
    profile_result = await db.execute(
        select(StudentProfile).where(StudentProfile.user_id == payload.student_id)
    )
    profile = profile_result.scalar_one_or_none()
    if profile and profile.parent_user_id:
        await redis_manager.publish({
            "target_type": "user",
            "user_id": profile.parent_user_id,
            "payload": {
                "event": "fee_payment_recorded",
                "amount": payload.amount,
                "notes": payload.notes,
            },
        })

    return payment


# ─── Payment Info (bank/UPI) ──────────────────────────────────────────────────

@router.get("/fees/payment-info", response_model=list[PaymentInfoResponse])
async def get_payment_info(
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Get all payment options (up to 3 slots)."""
    result = await db.execute(select(PaymentInfo).order_by(PaymentInfo.slot))
    return result.scalars().all()


@router.put("/fees/payment-info/{slot}", response_model=PaymentInfoResponse)
async def update_payment_info(
    slot: int,
    payload: PaymentInfoCreate,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Update or create a payment option by slot (1, 2, or 3)."""
    if slot not in (1, 2, 3):
        raise HTTPException(status_code=400, detail="Slot must be 1, 2, or 3.")
    result = await db.execute(select(PaymentInfo).where(PaymentInfo.slot == slot))
    info = result.scalar_one_or_none()
    if info:
        for field, value in payload.model_dump().items():
            setattr(info, field, value)
    else:
        info = PaymentInfo(slot=slot, **payload.model_dump())
        db.add(info)
    await db.commit()
    await db.refresh(info)
    return info


@router.post("/fees/payment-info/{slot}/qr", response_model=PaymentInfoResponse)
async def upload_qr_code(
    slot: int,
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Upload a QR code image for a specific payment slot."""
    if slot not in (1, 2, 3):
        raise HTTPException(status_code=400, detail="Slot must be 1, 2, or 3.")
    file_bytes = await file.read()
    ext = file.filename.rsplit(".", 1)[-1].lower() if file.filename else "png"
    key = f"payment/qr_code_slot{slot}.{ext}"
    url = await storage_service.upload_file("mindforge-profiles", key, file_bytes)

    result = await db.execute(select(PaymentInfo).where(PaymentInfo.slot == slot))
    info = result.scalar_one_or_none()
    if not info:
        info = PaymentInfo(slot=slot, qr_code_url=url)
        db.add(info)
    else:
        info.qr_code_url = url
    await db.commit()
    await db.refresh(info)
    return info


# ─── Timetable Config ─────────────────────────────────────────────────────────

@router.get("/timetable/config", response_model=Optional[TimetableConfigResponse])
async def get_timetable_config(
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Get the current timetable configuration."""
    result = await db.execute(select(TimetableConfig).order_by(TimetableConfig.id.desc()))
    return result.scalars().first()


@router.put("/timetable/config", response_model=TimetableConfigResponse)
async def update_timetable_config(
    payload: TimetableConfigCreate,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Update or create the global timetable configuration."""
    result = await db.execute(select(TimetableConfig).order_by(TimetableConfig.id.desc()))
    config = result.scalars().first()
    if config:
        config.periods_per_day = payload.periods_per_day
        config.enable_weekends = payload.enable_weekends
        config.period_times = payload.period_times
        config.created_by_admin_id = current_admin.id
    else:
        config = TimetableConfig(
            periods_per_day=payload.periods_per_day,
            enable_weekends=payload.enable_weekends,
            period_times=payload.period_times,
            created_by_admin_id=current_admin.id,
        )
        db.add(config)
    await db.commit()
    await db.refresh(config)
    from app.core.cache import invalidate_timetable_config
    await invalidate_timetable_config()

    # Broadcast timetable config change to all connected clients
    await redis_manager.publish({
        "target_type": "broadcast",
        "payload": {
            "event": "timetable_config_updated",
            "periods_per_day": payload.periods_per_day,
        },
    })

    return config


@router.delete("/timetable/slots", status_code=status.HTTP_200_OK)
async def clear_all_timetable_slots(
    grade: Optional[int] = None,
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Delete all timetable slots (or only for a specific grade if provided)."""
    from sqlalchemy import delete as sql_delete
    if grade is not None:
        await db.execute(sql_delete(TimetableSlot).where(TimetableSlot.grade == grade))
    else:
        await db.execute(sql_delete(TimetableSlot))
    await db.commit()
    return {"message": "Timetable slots cleared." if grade is None else f"Timetable slots for grade {grade} cleared."}


# ─── Academic Year ─────────────────────────────────────────────────────────────

def _make_year_label(year: int) -> str:
    """Generate label like '2025-26' from a start year."""
    return f"{year}-{str(year + 1)[-2:]}"


@router.get("/academic-years", response_model=List[dict])
async def get_academic_years(
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """List all academic years with user counts."""
    result = await db.execute(
        select(AcademicYear).order_by(AcademicYear.started_at.desc())
    )
    years = result.scalars().all()

    output = []
    for y in years:
        # Count users registered during this year
        count_result = await db.execute(
            select(sqlfunc.count(User.id)).where(
                User.academic_year_id == y.id,
                User.role != UserRole.admin,
            )
        )
        total = count_result.scalar() or 0

        # Count by role
        for_role = {}
        for role in (UserRole.student, UserRole.teacher, UserRole.parent):
            r = await db.execute(
                select(sqlfunc.count(User.id)).where(
                    User.academic_year_id == y.id,
                    User.role == role,
                )
            )
            for_role[role.value] = r.scalar() or 0

        output.append({
            "id": y.id,
            "year_label": y.year_label,
            "is_current": y.is_current,
            "started_at": y.started_at.isoformat(),
            "ended_at": y.ended_at.isoformat() if y.ended_at else None,
            "total_users": total,
            "students": for_role.get("student", 0),
            "teachers": for_role.get("teacher", 0),
            "parents": for_role.get("parent", 0),
        })
    return output


@router.get("/academic-years/current", response_model=Optional[dict])
async def get_current_academic_year(
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Return the currently active academic year, or null if none set."""
    result = await db.execute(
        select(AcademicYear).where(AcademicYear.is_current == True)
    )
    y = result.scalar_one_or_none()
    if not y:
        return None
    return {
        "id": y.id,
        "year_label": y.year_label,
        "is_current": y.is_current,
        "started_at": y.started_at.isoformat(),
        "ended_at": y.ended_at.isoformat() if y.ended_at else None,
    }


@router.get("/academic-years/{year_id}/users", response_model=List[UserWithProfileResponse])
async def get_users_by_year(
    year_id: int,
    role: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Return all users (any status) that belonged to a specific academic year."""
    query = (
        select(User, StudentProfile)
        .outerjoin(StudentProfile, StudentProfile.user_id == User.id)
        .where(User.academic_year_id == year_id, User.role != UserRole.admin)
    )
    if role:
        query = query.where(User.role == role)
    result = await db.execute(query.order_by(User.role, User.username))
    rows = result.all()
    return [
        UserWithProfileResponse(
            id=u.id, username=u.username, role=u.role,
            is_active=u.is_active, is_approved=u.is_approved,
            created_at=u.created_at, deleted_at=u.deleted_at,
            grade=p.grade if p else None,
            parent_user_id=p.parent_user_id if p else None,
        )
        for u, p in rows
    ]


@router.post("/academic-years/new", response_model=dict, status_code=status.HTTP_201_CREATED)
async def start_new_academic_year(
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """
    Start a new academic year:
    1. Close the current year (set ended_at).
    2. Soft-delete all non-admin users so they must re-register.
    3. Clear timetable slots.
    4. Create a new AcademicYear record marked as current.
    """
    now = datetime.now(timezone.utc)

    # 1. Close current year if one exists
    current_result = await db.execute(
        select(AcademicYear).where(AcademicYear.is_current == True)
    )
    current_year = current_result.scalar_one_or_none()
    if current_year:
        current_year.is_current = False
        current_year.ended_at = now

    # 2. Soft-delete all non-admin users
    non_admin_result = await db.execute(
        select(User).where(
            User.role != UserRole.admin,
            User.deleted_at.is_(None),
        )
    )
    for user in non_admin_result.scalars().all():
        user.deleted_at = now
        user.is_active = False
        user.is_approved = False

    # 3. Clear timetable slots (fresh slate for new year)
    slots_result = await db.execute(select(TimetableSlot))
    for slot in slots_result.scalars().all():
        await db.delete(slot)

    # 4. Create new academic year
    new_label = _make_year_label(now.year)
    new_year = AcademicYear(
        year_label=new_label,
        is_current=True,
        started_at=now,
        started_by_admin_id=current_admin.id,
    )
    db.add(new_year)
    await db.commit()
    await db.refresh(new_year)
    from app.core.cache import invalidate_academic_year
    await invalidate_academic_year()

    # Notify all connected clients
    await redis_manager.publish({
        "target_type": "broadcast",
        "payload": {
            "event": "new_academic_year",
            "year_label": new_label,
            "message": f"New academic year {new_label} has started. Please register again.",
        },
    })

    return {
        "id": new_year.id,
        "year_label": new_year.year_label,
        "is_current": new_year.is_current,
        "started_at": new_year.started_at.isoformat(),
    }


@router.post("/academic-years/init", response_model=dict, status_code=status.HTTP_201_CREATED)
async def init_academic_year(
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Create the first academic year (only if none exists yet)."""
    existing = await db.execute(select(AcademicYear))
    if existing.scalars().first():
        raise HTTPException(status_code=409, detail="Academic year already exists.")

    now = datetime.now(timezone.utc)
    label = _make_year_label(now.year)
    year = AcademicYear(
        year_label=label,
        is_current=True,
        started_at=now,
        started_by_admin_id=current_admin.id,
    )
    db.add(year)
    await db.commit()
    await db.refresh(year)
    return {
        "id": year.id,
        "year_label": year.year_label,
        "is_current": year.is_current,
        "started_at": year.started_at.isoformat(),
    }


# ─── Reports ──────────────────────────────────────────────────────────────────

@router.get("/reports/pending-fees")
async def download_pending_fees_report(
    academic_year: str = Query(...),
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Generate and stream a grade-wise pending fees PDF report."""
    students_result = await db.execute(
        select(User, StudentProfile)
        .join(StudentProfile, StudentProfile.user_id == User.id)
        .where(User.role == UserRole.student, User.deleted_at.is_(None), User.is_approved == True)
        .order_by(StudentProfile.grade, User.username)
    )
    rows = students_result.all()

    student_ids = [user.id for user, _ in rows]
    grades = {profile.grade for _, profile in rows}

    # Batch fetch: one query for all fee structures, one for all payments
    fs_result = await db.execute(
        select(FeeStructure).where(
            FeeStructure.academic_year == academic_year,
            FeeStructure.grade.in_(grades),
        )
    )
    fee_structures: dict[int, FeeStructure] = {fs.grade: fs for fs in fs_result.scalars().all()}

    payments_result = await db.execute(
        select(FeePayment)
        .where(FeePayment.student_id.in_(student_ids))
        .order_by(FeePayment.paid_at)
    )
    all_payments = payments_result.scalars().all()
    payments_by_student: dict[int, list] = {}
    for p in all_payments:
        payments_by_student.setdefault(p.student_id, []).append(p)

    summaries = []
    for user, profile in rows:
        fs = fee_structures.get(profile.grade)
        if fs:
            total_fee = float(fs.base_amount)
            for subj in (profile.additional_subjects or []):
                if subj == "economics":
                    total_fee += float(fs.economics_fee)
                elif subj == "computer":
                    total_fee += float(fs.computer_fee)
                elif subj == "ai":
                    total_fee += float(fs.ai_fee)
        else:
            total_fee = 0.0

        payments = payments_by_student.get(user.id, [])
        total_paid = sum(float(p.amount) for p in payments)

        summaries.append({
            "student_id": user.id,
            "username": user.username,
            "grade": profile.grade,
            "total_fee": total_fee,
            "total_paid": total_paid,
            "balance_due": max(0.0, total_fee - total_paid),
        })

    pdf_bytes = await pdf_service.generate_pending_fees_report(summaries, academic_year)
    filename = f"pending_fees_{academic_year.replace('-', '_')}.pdf"
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/reports/student-ledger/{student_id}")
async def download_student_ledger(
    student_id: int,
    academic_year: str = Query(...),
    db: AsyncSession = Depends(get_db),
    current_admin: User = Depends(get_current_admin),
):
    """Generate and stream a fee ledger PDF for a specific student."""
    result = await db.execute(
        select(User, StudentProfile)
        .join(StudentProfile, StudentProfile.user_id == User.id)
        .where(User.id == student_id, User.deleted_at.is_(None))
    )
    row = result.first()
    if not row:
        raise HTTPException(status_code=404, detail="Student not found.")
    user, profile = row

    fs_result = await db.execute(
        select(FeeStructure).where(
            FeeStructure.grade == profile.grade,
            FeeStructure.academic_year == academic_year,
        )
    )
    fs = fs_result.scalar_one_or_none()
    if fs:
        total_fee = float(fs.base_amount)
        for subj in (profile.additional_subjects or []):
            if subj == "economics":
                total_fee += float(fs.economics_fee)
            elif subj == "computer":
                total_fee += float(fs.computer_fee)
            elif subj == "ai":
                total_fee += float(fs.ai_fee)
    else:
        total_fee = 0.0

    payments_result = await db.execute(
        select(FeePayment).where(FeePayment.student_id == user.id).order_by(FeePayment.paid_at)
    )
    payments = payments_result.scalars().all()
    total_paid = sum(float(p.amount) for p in payments)

    # Build fee breakdown
    fee_breakdown = []
    if fs:
        fee_breakdown.append({"label": "Base Tuition Fee", "amount": float(fs.base_amount)})
        for subj in (profile.additional_subjects or []):
            if subj == "economics":
                fee_breakdown.append({"label": "Economics (Additional)", "amount": float(fs.economics_fee)})
            elif subj == "computer":
                fee_breakdown.append({"label": "Computer Applications (Additional)", "amount": float(fs.computer_fee)})
            elif subj == "ai":
                fee_breakdown.append({"label": "Artificial Intelligence (Additional)", "amount": float(fs.ai_fee)})

    student_data = {
        "username": user.username,
        "grade": profile.grade,
        "total_fee": total_fee,
        "total_paid": total_paid,
        "balance_due": max(0.0, total_fee - total_paid),
        "fee_breakdown": fee_breakdown,
        "payments": [
            {"id": p.id, "amount": float(p.amount), "paid_at": p.paid_at.isoformat(), "notes": p.notes}
            for p in payments
        ],
    }

    pdf_bytes = await pdf_service.generate_student_ledger_report(student_data, academic_year)
    filename = f"ledger_{user.username}_{academic_year.replace('-', '_')}.pdf"
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
