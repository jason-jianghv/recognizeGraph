"""全局物种目录：识别结果回填 + 唯一性 upsert。"""

from __future__ import annotations

import logging
import re
from typing import Iterable

from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.baidu.recognize import Candidate, Category
from app.db.models import CatalogSpecies, utcnow
from app.db.session import SessionLocal
from app.services.catalog_aliases import canonical_species_name

logger = logging.getLogger("shitu")

_WS = re.compile(r"\s+")


def normalize_species_name(name: str) -> str:
    """展示名规范化：去首尾空白、合并中间空白。唯一键用此结果。"""
    return _WS.sub(" ", (name or "").strip())


def candidate_ready_for_catalog(c: Candidate) -> bool:
    """探索列表需要图+简介；缺任一则不入库（避免空白卡不好看）。"""
    if not (c.image_url or "").strip():
        return False
    if not (c.description or "").strip():
        return False
    if not normalize_species_name(c.name):
        return False
    return True


def upsert_recognize_candidates(
    db: Session,
    category: Category | str,
    candidates: Iterable[Candidate],
) -> int:
    """将识别候选写入 catalog_species。

    - 不按可信度过滤（score 再低也可入库）
    - **须同时有 image_url + description**，否则跳过（探索展示用）
    - 同一 category + name 只保留一行；重复识别则更新字段并 seen_count+1
    - 单条失败不影响其它候选；整批异常不影响识别响应（由调用方吞掉）
    """
    cat = category.value if isinstance(category, Category) else str(category).strip()
    if cat not in {"animal", "plant", "transport"}:
        return 0

    touched = 0
    skipped = 0
    for c in candidates:
        raw = normalize_species_name(c.name)
        name = canonical_species_name(raw)
        if not name:
            continue
        if not candidate_ready_for_catalog(c):
            skipped += 1
            logger.info(
                "catalog skip incomplete name=%s has_img=%s has_desc=%s",
                name,
                bool((c.image_url or "").strip()),
                bool((c.description or "").strip()),
            )
            continue
        if raw != name:
            logger.info("catalog alias %s → %s", raw, name)
        try:
            if _upsert_one(db, cat, name, c):
                touched += 1
        except Exception:  # noqa: BLE001
            logger.exception(
                "catalog upsert failed category=%s name=%s", cat, name
            )
            try:
                db.rollback()
            except Exception:  # noqa: BLE001
                pass
            # rollback 后继续尝试后续候选（新事务）
    try:
        db.commit()
    except Exception:  # noqa: BLE001
        logger.exception("catalog commit failed")
        db.rollback()
        return 0
    if skipped:
        logger.info("catalog skipped %s incomplete candidates", skipped)
    return touched


def _upsert_one(db: Session, category: str, name: str, c: Candidate) -> bool:
    score = float(c.score or 0.0)
    now = utcnow()

    row = db.scalar(
        select(CatalogSpecies).where(
            CatalogSpecies.category == category,
            CatalogSpecies.name == name,
        )
    )
    if row is not None:
        _merge_into(row, c, score, now)
        return True

    # 并发下可能撞唯一约束：用 savepoint，避免整单回滚
    try:
        with db.begin_nested():
            row = CatalogSpecies(
                category=category,
                name=name,
                candidate_id=(c.id or "").strip() or f"baidu:{category}:{name}",
                one_liner=(c.one_liner or "").strip(),
                description=(c.description or "").strip(),
                baike_url=(c.baike_url or "").strip(),
                image_url=(c.image_url or "").strip(),
                last_score=score,
                best_score=score,
                seen_count=1,
                source="recognize",
                enrich_status="",
                is_common=1,
                created_at=now,
                updated_at=now,
            )
            db.add(row)
            db.flush()
        return True
    except IntegrityError:
        row = db.scalar(
            select(CatalogSpecies).where(
                CatalogSpecies.category == category,
                CatalogSpecies.name == name,
            )
        )
        if row is None:
            raise
        _merge_into(row, c, score, now)
        return True


def _merge_into(row: CatalogSpecies, c: Candidate, score: float, now) -> None:
    row.seen_count = int(row.seen_count or 0) + 1
    row.last_score = score
    row.best_score = max(float(row.best_score or 0.0), score)
    row.updated_at = now
    # 用户识别过的条目视为常规，可进探索
    row.is_common = 1
    cid = (c.id or "").strip()
    if cid:
        row.candidate_id = cid
    # 有内容才覆盖，避免空字段抹掉已有百科
    one = (c.one_liner or "").strip()
    if one:
        row.one_liner = one
    desc = (c.description or "").strip()
    if desc and (not row.description or len(desc) >= len(row.description)):
        row.description = desc
    baike = (c.baike_url or "").strip()
    if baike:
        row.baike_url = baike
    img = (c.image_url or "").strip()
    if img:
        row.image_url = img


def purge_incomplete_recognize_rows(db: Session | None = None) -> int:
    """删掉识别回填但缺图或缺简介的目录行（历史脏数据）。"""
    own = db is None
    session = db or SessionLocal()
    try:
        rows = list(
            session.scalars(
                select(CatalogSpecies).where(
                    CatalogSpecies.source == "recognize",
                    or_(
                        CatalogSpecies.image_url.is_(None),
                        CatalogSpecies.image_url == "",
                        CatalogSpecies.description.is_(None),
                        CatalogSpecies.description == "",
                    ),
                )
            ).all()
        )
        n = len(rows)
        for row in rows:
            session.delete(row)
        session.commit()
        if n:
            logger.info("catalog purged %s incomplete recognize rows", n)
        return n
    except Exception:
        logger.exception("catalog purge incomplete failed")
        session.rollback()
        return 0
    finally:
        if own:
            session.close()
