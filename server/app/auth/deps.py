from __future__ import annotations

from typing import Optional

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.db.models import Session as DbSession
from app.db.models import User
from app.db.session import get_db

_bearer = HTTPBearer(auto_error=False)


def get_current_user(
    creds: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
    db: Session = Depends(get_db),
) -> User:
    if creds is None or not creds.credentials:
        raise HTTPException(status_code=401, detail="请先登录")
    token = creds.credentials.strip()
    row = db.get(DbSession, token)
    if row is None:
        raise HTTPException(status_code=401, detail="登录已失效，请重新登录")
    user = db.get(User, row.user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="用户不存在")
    return user
