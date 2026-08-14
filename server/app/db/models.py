from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


from app.auth.levels import level_from_learn_count, next_level_progress


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    phone: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    nickname: Mapped[str] = mapped_column(String(64), default="")
    avatar_url: Mapped[str] = mapped_column(String(512), default="")
    learn_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    last_login_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    sessions: Mapped[list[Session]] = relationship(back_populates="user")
    records: Mapped[list[LearningRecord]] = relationship(back_populates="user")

    @property
    def level(self) -> int:
        return level_from_learn_count(self.learn_count)

    @property
    def next_level(self) -> int | None:
        _, nxt, _ = next_level_progress(self.learn_count)
        return nxt

    @property
    def learns_to_next(self) -> int | None:
        _, _, remain = next_level_progress(self.learn_count)
        return remain


class Session(Base):
    __tablename__ = "sessions"

    token: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    user: Mapped[User] = relationship(back_populates="sessions")


class LearningRecord(Base):
    __tablename__ = "learning_records"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    category: Mapped[str] = mapped_column(String(32), default="")
    name: Mapped[str] = mapped_column(String(128))
    candidate_id: Mapped[str] = mapped_column(String(128), default="")
    baike_url: Mapped[str] = mapped_column(String(512), default="")
    image_url: Mapped[str] = mapped_column(String(512), default="")
    # 百科/介绍正文（详情页名称下方那段，与识别结果一致）
    description: Mapped[str] = mapped_column(Text, default="")
    score: Mapped[float] = mapped_column(Float, default=0.0)
    source: Mapped[str] = mapped_column(String(32), default="recognize")
    # 相对 server 的路径，如 thumbs/u1/xxx.jpg；对外用 /media/...
    thumb_relpath: Mapped[str] = mapped_column(String(512), default="")
    year_month: Mapped[str] = mapped_column(String(7), index=True)  # YYYY-MM
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    user: Mapped[User] = relationship(back_populates="records")


class CatalogSpecies(Base):
    """全局物种/品类目录（探索列表真源；与用户学习历史解耦）。

    唯一性：同一 category 下 name（规范化后）只保留一行。
    """

    __tablename__ = "catalog_species"
    __table_args__ = (
        UniqueConstraint("category", "name", name="uq_catalog_category_name"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    category: Mapped[str] = mapped_column(String(32), index=True)  # animal|plant|transport
    name: Mapped[str] = mapped_column(String(128))
    candidate_id: Mapped[str] = mapped_column(String(128), default="", index=True)
    one_liner: Mapped[str] = mapped_column(String(256), default="")
    description: Mapped[str] = mapped_column(Text, default="")
    baike_url: Mapped[str] = mapped_column(String(512), default="")
    image_url: Mapped[str] = mapped_column(String(512), default="")
    # 最近一次识别分；best_score 取历史最高（可信度不设门槛，低分也可入库）
    last_score: Mapped[float] = mapped_column(Float, default=0.0)
    best_score: Mapped[float] = mapped_column(Float, default=0.0)
    seen_count: Mapped[int] = mapped_column(Integer, default=1)
    # recognize = 识别回填；seed = 词表种子；wiki = 维基补简介
    source: Mapped[str] = mapped_column(String(32), default="recognize")
    # '' | ok | miss — 简介补齐结果，miss 时不反复打百科
    enrich_status: Mapped[str] = mapped_column(String(16), default="")
    # 探索默认只展示常规物种；生僻 tropials 可留库但不进探索
    is_common: Mapped[int] = mapped_column(Integer, default=1, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
