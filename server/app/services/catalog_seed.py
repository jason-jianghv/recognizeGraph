"""从 name_en 词表种子「常规」物种到 catalog_species（幂等）。

策略：
- 新插入：仅 seed / transport_seed（儿童向精校）；**暂不新加** tropials 生僻种
- 已入库的 tropials **不删除**，仅标记 is_common=0，探索默认不展示
- 近义别名收束为规范名；别名行/个例昵称探索隐藏
"""

from __future__ import annotations

import json
import logging
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import CatalogSpecies, utcnow
from app.db.session import SessionLocal
from app.services.catalog import normalize_species_name
from app.services.catalog_aliases import (
    SPECIES_ALIASES,
    canonical_species_name,
    should_hide_from_explore,
)

logger = logging.getLogger("shitu")

_RESOURCES = Path(__file__).resolve().parents[2] / "resources" / "name_en"
_SPECIES_JSON = _RESOURCES / "zh_en_species.json"

# 允许新写入目录的词表来源（常规）
_COMMON_SOURCES = frozenset({"seed", "transport_seed"})
# 生僻来源：已有行保留，仅标 is_common=0
_OBSCURE_SOURCES = frozenset({"tropicals"})


def _seedable_name(name: str) -> bool:
    if len(name) < 2 or len(name) > 64:
        return False
    if name.count("(") != name.count(")"):
        return False
    if name.endswith(("(", "（")):
        return False
    if "泛指" in name:
        return False
    return True


def _load_entries() -> list[dict]:
    if not _SPECIES_JSON.is_file():
        return []
    payload = json.loads(_SPECIES_JSON.read_text(encoding="utf-8"))
    entries = payload.get("entries") or []
    return entries if isinstance(entries, list) else []


def mark_common_flags_from_lexicon(db: Session | None = None) -> dict[str, int]:
    """按词表 source 回填 is_common：seed/transport=1，tropicals=0；不删行。

    另：近义别名/个例昵称强制 is_common=0（探索不展示）。
    """
    own = db is None
    session = db or SessionLocal()
    stats = {
        "marked_common": 0,
        "marked_obscure": 0,
        "marked_alias_hidden": 0,
        "unchanged": 0,
    }
    try:
        entries = _load_entries()
        if not entries:
            return stats

        common_names: set[tuple[str, str]] = set()
        obscure_names: set[tuple[str, str]] = set()
        for ent in entries:
            cat = str(ent.get("category") or "").strip()
            src = str(ent.get("source") or "").strip()
            raw = normalize_species_name(str(ent.get("zh") or ""))
            if cat not in {"animal", "plant", "transport"} or not raw:
                continue
            if should_hide_from_explore(raw):
                continue
            name = canonical_species_name(raw)
            key = (cat, name)
            if src in _COMMON_SOURCES:
                common_names.add(key)
            elif src in _OBSCURE_SOURCES:
                obscure_names.add(key)

        rows = list(session.scalars(select(CatalogSpecies)).all())
        for row in rows:
            if should_hide_from_explore(row.name):
                if int(row.is_common or 0) != 0:
                    row.is_common = 0
                    stats["marked_alias_hidden"] += 1
                else:
                    stats["unchanged"] += 1
                continue

            key = (row.category, row.name)
            if (row.source or "") == "recognize":
                if int(row.is_common or 0) != 1:
                    row.is_common = 1
                    stats["marked_common"] += 1
                else:
                    stats["unchanged"] += 1
                continue
            if key in common_names:
                if int(row.is_common or 0) != 1:
                    row.is_common = 1
                    stats["marked_common"] += 1
                else:
                    stats["unchanged"] += 1
            elif key in obscure_names:
                if int(row.is_common or 0) != 0:
                    row.is_common = 0
                    stats["marked_obscure"] += 1
                else:
                    stats["unchanged"] += 1
            else:
                stats["unchanged"] += 1
        session.commit()
        logger.info("catalog is_common mark stats=%s", stats)
        return stats
    except Exception:
        logger.exception("mark_common_flags_from_lexicon failed")
        session.rollback()
        raise
    finally:
        if own:
            session.close()


def seed_catalog_from_name_en(db: Session | None = None) -> dict[str, int]:
    """把词表中的「常规」条目写入目录。

    - 仅插入尚不存在的 (category, name)
    - 仅 seed / transport_seed；跳过 tropials（生僻暂不加）
    - 别名收束为规范名，不单独插入别名行
    - 不覆盖识别回填已有的百科字段
    """
    own = db is None
    session = db or SessionLocal()
    stats = {
        "inserted": 0,
        "skipped_existing": 0,
        "skipped_bad": 0,
        "skipped_obscure": 0,
        "skipped_alias": 0,
        "total_file": 0,
    }
    try:
        entries = _load_entries()
        if not entries:
            logger.warning("catalog seed skipped: missing %s", _SPECIES_JSON)
            return stats
        stats["total_file"] = len(entries)

        existing = {
            (str(cat), str(name))
            for cat, name in session.execute(
                select(CatalogSpecies.category, CatalogSpecies.name)
            ).all()
        }

        now = utcnow()
        batch: list[CatalogSpecies] = []
        for ent in entries:
            cat = str(ent.get("category") or "").strip()
            src = str(ent.get("source") or "").strip()
            if cat not in {"animal", "plant", "transport"}:
                stats["skipped_bad"] += 1
                continue
            if src not in _COMMON_SOURCES:
                if src in _OBSCURE_SOURCES:
                    stats["skipped_obscure"] += 1
                else:
                    stats["skipped_bad"] += 1
                continue
            raw = normalize_species_name(str(ent.get("zh") or ""))
            if not _seedable_name(raw):
                stats["skipped_bad"] += 1
                continue
            if raw in SPECIES_ALIASES:
                stats["skipped_alias"] += 1
                name = canonical_species_name(raw)
            else:
                name = raw
            if not _seedable_name(name):
                stats["skipped_bad"] += 1
                continue
            key = (cat, name)
            if key in existing:
                stats["skipped_existing"] += 1
                continue
            existing.add(key)
            batch.append(
                CatalogSpecies(
                    category=cat,
                    name=name,
                    candidate_id=f"seed:{cat}:{name}",
                    one_liner=f"认识一下「{name}」吧～",
                    description="",
                    baike_url="",
                    image_url="",
                    last_score=0.0,
                    best_score=0.0,
                    seen_count=1,
                    source="seed",
                    enrich_status="",
                    is_common=1,
                    created_at=now,
                    updated_at=now,
                )
            )
            stats["inserted"] += 1
            if len(batch) >= 400:
                session.add_all(batch)
                session.commit()
                batch.clear()

        if batch:
            session.add_all(batch)
            session.commit()

        logger.info(
            "catalog seed done inserted=%s skipped_existing=%s "
            "skipped_obscure=%s skipped_alias=%s skipped_bad=%s file=%s",
            stats["inserted"],
            stats["skipped_existing"],
            stats["skipped_obscure"],
            stats["skipped_alias"],
            stats["skipped_bad"],
            stats["total_file"],
        )
        return stats
    except Exception:
        logger.exception("catalog seed failed")
        session.rollback()
        raise
    finally:
        if own:
            session.close()


def ensure_catalog_seeded() -> None:
    """启动：清理不完整识别回填 → 只补常规种子 → 标记 is_common。"""
    try:
        from app.services.catalog import purge_incomplete_recognize_rows

        purged = purge_incomplete_recognize_rows()
        if purged:
            logger.info("catalog purged incomplete recognize=%s", purged)
        stats = seed_catalog_from_name_en()
        logger.info("catalog ensure seed stats=%s", stats)
        flags = mark_common_flags_from_lexicon()
        logger.info("catalog is_common flags=%s", flags)
    except Exception:
        logger.exception("ensure_catalog_seeded failed")
