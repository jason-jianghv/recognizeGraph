"""学习排行榜（P-015）：总榜 + 自然周周榜。

- 总榜：按 users.learn_count（与空间已学次数同源）
- 周榜：按本自然周（周一 00:00～下周一 00:00，Asia/Shanghai）内 learning_records 条数
- 名次：竞赛排名（同分同名次）= 1 + 分数严格更高的用户数
- 榜单只展示次数 >0 的用户前 20；`me` 在带合法 Bearer 时返回
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import List, Literal, Optional, Sequence, Tuple
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import desc, func
from sqlalchemy.orm import Session

from app.auth.deps import get_optional_user
from app.auth.levels import level_from_learn_count
from app.db.models import LearningRecord, User
from app.db.session import get_db

router = APIRouter(prefix="/v1/leaderboard", tags=["leaderboard"])

_CN_TZ = ZoneInfo("Asia/Shanghai")
_DEFAULT_LIMIT = 20
_MAX_LIMIT = 50


class LeaderboardEntry(BaseModel):
    rank: int
    user_id: int
    nickname: str
    avatar_url: str
    learn_count: int
    level: int


class MeRank(BaseModel):
    rank: Optional[int] = None
    learn_count: int
    nickname: str
    avatar_url: str
    level: int
    in_top: bool


class LeaderboardResponse(BaseModel):
    scope: Literal["total", "week"]
    limit: int
    week_start: Optional[str] = None  # ISO，仅 week
    week_end: Optional[str] = None  # ISO 开区间上界，仅 week
    items: List[LeaderboardEntry]
    me: Optional[MeRank] = None


def natural_week_bounds_utc(
    now: Optional[datetime] = None,
) -> Tuple[datetime, datetime]:
    """当前自然周 [周一 00:00, 下周一 00:00) 的 UTC 边界（按上海时区）。"""
    now_utc = now or datetime.now(timezone.utc)
    if now_utc.tzinfo is None:
        now_utc = now_utc.replace(tzinfo=timezone.utc)
    local = now_utc.astimezone(_CN_TZ)
    start_local = (local - timedelta(days=local.weekday())).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    end_local = start_local + timedelta(days=7)
    return start_local.astimezone(timezone.utc), end_local.astimezone(timezone.utc)


def _competition_ranks(counts: Sequence[int]) -> List[int]:
    """counts 已按降序；同分同名次（竞赛排名）。"""
    ranks: List[int] = []
    prev_count: Optional[int] = None
    prev_rank = 0
    for i, c in enumerate(counts):
        if prev_count is None or c != prev_count:
            rank = i + 1
        else:
            rank = prev_rank
        ranks.append(rank)
        prev_count = c
        prev_rank = rank
    return ranks


def _entry(
    *,
    rank: int,
    user_id: int,
    nickname: str,
    avatar_url: str,
    learn_count: int,
    total_learn_count: int,
) -> LeaderboardEntry:
    return LeaderboardEntry(
        rank=rank,
        user_id=user_id,
        nickname=nickname or "",
        avatar_url=avatar_url or "",
        learn_count=int(learn_count),
        level=level_from_learn_count(total_learn_count),
    )


def _me_payload(
    *,
    me: User,
    my_count: int,
    rank: int,
    level_from_total: int,
    top_ids: set,
) -> MeRank:
    return MeRank(
        rank=rank,
        learn_count=int(my_count),
        nickname=me.nickname or "",
        avatar_url=me.avatar_url or "",
        level=level_from_total,
        in_top=me.id in top_ids,
    )


def _total_board(
    db: Session, limit: int, me: Optional[User]
) -> LeaderboardResponse:
    rows = (
        db.query(User)
        .filter(User.learn_count > 0)
        .order_by(desc(User.learn_count), User.id.asc())
        .limit(limit)
        .all()
    )
    ranks = _competition_ranks([int(u.learn_count or 0) for u in rows])
    items = [
        _entry(
            rank=ranks[i],
            user_id=u.id,
            nickname=u.nickname,
            avatar_url=u.avatar_url,
            learn_count=int(u.learn_count or 0),
            total_learn_count=int(u.learn_count or 0),
        )
        for i, u in enumerate(rows)
    ]

    me_payload: Optional[MeRank] = None
    if me is not None:
        my_count = int(me.learn_count or 0)
        if my_count > 0:
            higher = (
                db.query(func.count(User.id))
                .filter(User.learn_count > my_count)
                .scalar()
                or 0
            )
            rank = int(higher) + 1
        else:
            learners = (
                db.query(func.count(User.id)).filter(User.learn_count > 0).scalar()
                or 0
            )
            rank = int(learners) + 1 if learners else 1
        me_payload = _me_payload(
            me=me,
            my_count=my_count,
            rank=rank,
            level_from_total=level_from_learn_count(my_count),
            top_ids={e.user_id for e in items},
        )

    return LeaderboardResponse(scope="total", limit=limit, items=items, me=me_payload)


def _week_counts_subq(db: Session, start: datetime, end: datetime):
    return (
        db.query(
            LearningRecord.user_id.label("user_id"),
            func.count(LearningRecord.id).label("cnt"),
        )
        .filter(
            LearningRecord.created_at >= start,
            LearningRecord.created_at < end,
        )
        .group_by(LearningRecord.user_id)
        .subquery()
    )


def _week_board(
    db: Session, limit: int, me: Optional[User]
) -> LeaderboardResponse:
    start, end = natural_week_bounds_utc()
    subq = _week_counts_subq(db, start, end)

    rows = (
        db.query(User, subq.c.cnt)
        .join(subq, User.id == subq.c.user_id)
        .filter(subq.c.cnt > 0)
        .order_by(desc(subq.c.cnt), User.id.asc())
        .limit(limit)
        .all()
    )
    counts = [int(cnt) for _, cnt in rows]
    ranks = _competition_ranks(counts)
    items = [
        _entry(
            rank=ranks[i],
            user_id=u.id,
            nickname=u.nickname,
            avatar_url=u.avatar_url,
            learn_count=counts[i],
            total_learn_count=int(u.learn_count or 0),
        )
        for i, (u, _) in enumerate(rows)
    ]

    me_payload: Optional[MeRank] = None
    if me is not None:
        my_count = int(
            db.query(func.count(LearningRecord.id))
            .filter(
                LearningRecord.user_id == me.id,
                LearningRecord.created_at >= start,
                LearningRecord.created_at < end,
            )
            .scalar()
            or 0
        )
        if my_count > 0:
            higher = (
                db.query(func.count())
                .select_from(subq)
                .filter(subq.c.cnt > my_count)
                .scalar()
                or 0
            )
            rank = int(higher) + 1
        else:
            week_learners = db.query(func.count()).select_from(subq).scalar() or 0
            rank = int(week_learners) + 1 if week_learners else 1
        me_payload = _me_payload(
            me=me,
            my_count=my_count,
            rank=rank,
            level_from_total=level_from_learn_count(int(me.learn_count or 0)),
            top_ids={e.user_id for e in items},
        )

    return LeaderboardResponse(
        scope="week",
        limit=limit,
        week_start=start.isoformat(),
        week_end=end.isoformat(),
        items=items,
        me=me_payload,
    )


@router.get("", response_model=LeaderboardResponse)
async def get_leaderboard(
    scope: Literal["total", "week"] = Query(
        "total", description="total=总榜；week=本自然周周榜"
    ),
    limit: int = Query(_DEFAULT_LIMIT, ge=1, le=_MAX_LIMIT),
    db: Session = Depends(get_db),
    me: Optional[User] = Depends(get_optional_user),
) -> LeaderboardResponse:
    if scope == "total":
        return _total_board(db, limit, me)
    if scope == "week":
        return _week_board(db, limit, me)
    raise HTTPException(status_code=400, detail="scope 仅支持 total 或 week")
