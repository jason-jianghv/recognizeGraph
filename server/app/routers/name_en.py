"""详情页：中文名 → 英文名（词表 + 机翻兜底）。"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from app.services.name_en import resolve_name_en

router = APIRouter(prefix="/v1/name-en", tags=["name-en"])


class NameEnBody(BaseModel):
    name: str = Field(..., description="中文名称")
    allow_translate: bool = Field(True, description="词表未命中时是否机翻")


@router.get("")
async def get_name_en(
    name: str = Query(..., min_length=1, description="中文名称"),
    allow_translate: bool = Query(True),
) -> dict:
    result = await resolve_name_en(name, allow_translate=allow_translate)
    return dict(result)


@router.post("")
async def post_name_en(body: NameEnBody) -> dict:
    name = (body.name or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="name 不能为空")
    result = await resolve_name_en(name, allow_translate=body.allow_translate)
    return dict(result)
