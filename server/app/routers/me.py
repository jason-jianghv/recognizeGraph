from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.auth.deps import get_current_user
from app.db.models import User

router = APIRouter(prefix="/v1", tags=["me"])


class MeResponse(BaseModel):
    phone: str
    nickname: str
    avatar_url: str
    learn_count: int
    level: int
    next_level: Optional[int] = None
    learns_to_next: Optional[int] = None
    level_hint: str = ""


@router.get("/me", response_model=MeResponse)
async def me(user: User = Depends(get_current_user)) -> MeResponse:
    from app.auth.levels import level_hint

    return MeResponse(
        phone=user.phone,
        nickname=user.nickname,
        avatar_url=user.avatar_url or "",
        learn_count=user.learn_count,
        level=user.level,
        next_level=user.next_level,
        learns_to_next=user.learns_to_next,
        level_hint=level_hint(user.learn_count),
    )
