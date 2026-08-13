from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from pydantic import BaseModel
from sqlalchemy import desc, func
from sqlalchemy.orm import Session

from app.auth.deps import get_current_user
from app.auth.levels import level_hint
from app.db.models import LearningRecord, User
from app.db.session import get_db
from app.services.thumbs import save_user_thumb, thumb_public_url, year_month_now

router = APIRouter(prefix="/v1/history", tags=["history"])


class MonthItem(BaseModel):
    year_month: str
    count: int


class MonthsResponse(BaseModel):
    months: list[MonthItem]


class HistoryItem(BaseModel):
    id: int
    name: str
    category: str
    candidate_id: str
    baike_url: str
    image_url: str
    description: str = ""
    score: float
    source: str
    thumb_url: str
    year_month: str
    created_at: str


class HistoryPage(BaseModel):
    year_month: str
    page: int
    page_size: int
    total: int
    items: list[HistoryItem]


class CreateHistoryResponse(BaseModel):
    id: int
    learn_count: int
    level: int
    thumb_url: str
    next_level: Optional[int] = None
    learns_to_next: Optional[int] = None
    level_hint: str = ""


def _item(rec: LearningRecord) -> HistoryItem:
    return HistoryItem(
        id=rec.id,
        name=rec.name,
        category=rec.category,
        candidate_id=rec.candidate_id,
        baike_url=rec.baike_url,
        image_url=rec.image_url,
        description=rec.description or "",
        score=rec.score,
        source=rec.source,
        thumb_url=thumb_public_url(rec.thumb_relpath),
        year_month=rec.year_month,
        created_at=rec.created_at.isoformat() if rec.created_at else "",
    )


@router.get("/months", response_model=MonthsResponse)
async def list_months(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> MonthsResponse:
    rows = (
        db.query(LearningRecord.year_month, func.count(LearningRecord.id))
        .filter(LearningRecord.user_id == user.id)
        .group_by(LearningRecord.year_month)
        .order_by(desc(LearningRecord.year_month))
        .all()
    )
    return MonthsResponse(
        months=[MonthItem(year_month=ym, count=int(c)) for ym, c in rows]
    )


@router.get("", response_model=HistoryPage)
async def list_history(
    month: str = Query(..., description="YYYY-MM"),
    page: int = Query(1, ge=1),
    page_size: int = Query(21, ge=1, le=60),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> HistoryPage:
    month = (month or "").strip()
    if len(month) != 7 or month[4] != "-":
        raise HTTPException(status_code=400, detail="month 格式应为 YYYY-MM")

    q = db.query(LearningRecord).filter(
        LearningRecord.user_id == user.id,
        LearningRecord.year_month == month,
    )
    total = q.count()
    items = (
        q.order_by(desc(LearningRecord.created_at), desc(LearningRecord.id))
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
    return HistoryPage(
        year_month=month,
        page=page,
        page_size=page_size,
        total=total,
        items=[_item(r) for r in items],
    )


@router.post("", response_model=CreateHistoryResponse)
async def create_history(
    name: str = Form(...),
    category: str = Form(""),
    candidate_id: str = Form(""),
    baike_url: str = Form(""),
    image_url: str = Form(""),
    description: str = Form(""),
    score: float = Form(0),
    source: str = Form("recognize"),
    thumb: Optional[UploadFile] = File(None),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> CreateHistoryResponse:
    name = (name or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="名称不能为空")

    thumb_rel = ""
    if thumb is not None:
        raw = await thumb.read()
        if raw:
            try:
                thumb_rel = save_user_thumb(user.id, raw)
            except Exception as e:  # noqa: BLE001
                raise HTTPException(status_code=400, detail=f"缩略图处理失败：{e}") from e

    rec = LearningRecord(
        user_id=user.id,
        category=(category or "").strip(),
        name=name,
        candidate_id=(candidate_id or "").strip(),
        baike_url=(baike_url or "").strip(),
        image_url=(image_url or "").strip(),
        description=(description or "").strip(),
        score=float(score or 0),
        source=(source or "recognize").strip() or "recognize",
        thumb_relpath=thumb_rel,
        year_month=year_month_now(),
    )
    user.learn_count = int(user.learn_count or 0) + 1
    db.add(rec)
    db.add(user)
    db.commit()
    db.refresh(rec)
    db.refresh(user)

    return CreateHistoryResponse(
        id=rec.id,
        learn_count=user.learn_count,
        level=user.level,
        thumb_url=thumb_public_url(rec.thumb_relpath),
        next_level=user.next_level,
        learns_to_next=user.learns_to_next,
        level_hint=level_hint(user.learn_count),
    )
