from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.auth.codes import sms_store
from app.auth.phone import require_valid_cn_mobile
from app.db.models import Session as DbSession
from app.db.models import User
from app.db.session import get_db

router = APIRouter(prefix="/v1/auth", tags=["auth"])
_bearer = HTTPBearer(auto_error=False)


class SmsCodeRequest(BaseModel):
    phone: str = Field(..., description="大陆手机号，11 位")


class SmsCodeResponse(BaseModel):
    phone: str
    expires_in: int
    resend_after: int
    # MVP：明文返回验证码供 App Toast；接短信后务必删除此字段
    code: str


class LoginRequest(BaseModel):
    phone: str
    code: str = Field(..., min_length=4, max_length=8)


class LoginResponse(BaseModel):
    token: str
    phone: str
    nickname: str
    avatar_url: str
    learn_count: int
    level: int
    next_level: Optional[int] = None
    learns_to_next: Optional[int] = None
    level_hint: str = ""


@router.post("/sms-code", response_model=SmsCodeResponse)
async def send_sms_code(body: SmsCodeRequest) -> SmsCodeResponse:
    try:
        phone = require_valid_cn_mobile(body.phone)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    try:
        code, expires_in, resend_after = sms_store.issue_sms_code(phone)
    except ValueError as e:
        raise HTTPException(status_code=429, detail=str(e)) from e

    return SmsCodeResponse(
        phone=phone,
        expires_in=expires_in,
        resend_after=resend_after,
        code=code,
    )


@router.post("/login", response_model=LoginResponse)
async def login(body: LoginRequest, db: Session = Depends(get_db)) -> LoginResponse:
    try:
        phone = require_valid_cn_mobile(body.phone)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    try:
        sms_store.verify_and_consume(phone, body.code)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    user = db.query(User).filter(User.phone == phone).one_or_none()
    now = datetime.now(timezone.utc)
    if user is None:
        user = User(
            phone=phone,
            nickname=f"探索家{phone[-4:]}",
            avatar_url="",
            learn_count=0,
            created_at=now,
            last_login_at=now,
        )
        db.add(user)
        db.flush()
    else:
        user.last_login_at = now

    token = uuid.uuid4().hex
    db.add(DbSession(token=token, user_id=user.id, created_at=now))
    db.commit()
    db.refresh(user)

    from app.auth.levels import level_hint

    return LoginResponse(
        token=token,
        phone=user.phone,
        nickname=user.nickname,
        avatar_url=user.avatar_url or "",
        learn_count=user.learn_count,
        level=user.level,
        next_level=user.next_level,
        learns_to_next=user.learns_to_next,
        level_hint=level_hint(user.learn_count),
    )


@router.post("/logout")
async def logout(
    creds: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
    db: Session = Depends(get_db),
) -> dict:
    if creds and creds.credentials:
        row = db.get(DbSession, creds.credentials.strip())
        if row is not None:
            db.delete(row)
            db.commit()
    return {"ok": True}
