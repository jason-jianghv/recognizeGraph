from __future__ import annotations

from typing import Optional

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.db.models import Session as DbSession
from app.db.models import User
from app.db.session import get_db

_bearer = HTTPBearer(auto_error=False)


def _user_from_bearer(
    creds: Optional[HTTPAuthorizationCredentials],
    db: Session,
    *,
    required: bool,
) -> Optional[User]:
    if creds is None or not creds.credentials:
        if required:
            raise HTTPException(status_code=401, detail="请先登录")
        return None
    token = creds.credentials.strip()
    row = db.get(DbSession, token)
    if row is None:
        if required:
            raise HTTPException(status_code=401, detail="登录已失效，请重新登录")
        return None
    user = db.get(User, row.user_id)
    if user is None:
        if required:
            raise HTTPException(status_code=401, detail="用户不存在")
        return None
    return user


def get_current_user(
    creds: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
    db: Session = Depends(get_db),
) -> User:
    user = _user_from_bearer(creds, db, required=True)
    assert user is not None
    return user


def get_optional_user(
    creds: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
    db: Session = Depends(get_db),
) -> Optional[User]:
    """有合法 Bearer 则返回用户；无 token / 失效则 None（不 401）。"""
    return _user_from_bearer(creds, db, required=False)
