"""为 catalog_species 补齐简介（维基百科摘要）。"""

from __future__ import annotations

import json
import logging
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.models import CatalogSpecies, utcnow
from app.services.wiki_summary import (
    WikiFetchError,
    WikiSummary,
    fetch_summary_for_species,
    fetch_summaries_for_species_batch,
    one_liner_from_extract,
    with_retries,
)

logger = logging.getLogger("shitu")

_RESOURCES = Path(__file__).resolve().parents[2] / "resources" / "name_en"
_MAP_JSON = _RESOURCES / "zh_en_map.json"

_SEED_ONE_PREFIX = "认识一下「"


def _load_en_map() -> dict[str, str]:
    if not _MAP_JSON.is_file():
        return {}
    try:
        data = json.loads(_MAP_JSON.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    if isinstance(data, dict):
        # may be {"entries":...} or flat zh->en
        if "entries" in data and isinstance(data["entries"], list):
            out: dict[str, str] = {}
            for ent in data["entries"]:
                zh = str(ent.get("zh") or "").strip()
                en = str(ent.get("en") or "").strip()
                if zh and en:
                    out[zh] = en
            return out
        return {str(k): str(v) for k, v in data.items() if k not in {"version", "license_notes", "counts"}}
    return {}


_EN_MAP: dict[str, str] | None = None


def en_name_for(zh: str) -> str:
    global _EN_MAP
    if _EN_MAP is None:
        _EN_MAP = _load_en_map()
    return (_EN_MAP or {}).get(zh, "")


def needs_description_enrich(row: CatalogSpecies) -> bool:
    """缺简介且未确认 miss。"""
    if (row.enrich_status or "") == "miss":
        return False
    if (row.description or "").strip():
        return False
    return True


def needs_image_enrich(row: CatalogSpecies) -> bool:
    """缺配图；有简介但无图的也补。"""
    return not (row.image_url or "").strip()


def needs_catalog_enrich(row: CatalogSpecies) -> bool:
    """缺简介或缺图（简介 miss 且无图则不再打维基）。"""
    if needs_description_enrich(row):
        return True
    if needs_image_enrich(row) and (row.enrich_status or "") != "miss":
        return True
    return False


def _looks_like_seed_one_liner(text: str, name: str) -> bool:
    t = (text or "").strip()
    if not t:
        return True
    if t.startswith(_SEED_ONE_PREFIX):
        return True
    if t in {f"点进去了解一下～", f"认识一下「{name}」吧～"}:
        return True
    return False


def _looks_like_weak_description(text: str) -> bool:
    """英文消歧页、过短或几乎全 ASCII 的简介，允许被中文维基覆盖。"""
    t = (text or "").strip()
    if not t:
        return True
    low = t.lower()
    if "may refer to" in low or "disambiguation" in low:
        return True
    if len(t) < 40:
        return True
    ascii_n = sum(1 for c in t if ord(c) < 128)
    if ascii_n / max(len(t), 1) > 0.75:
        return True
    return False


async def enrich_catalog_row(db: Session, row: CatalogSpecies) -> bool:
    """若缺简介/配图则打维基并写回。成功 True；确认无词条记 miss；临时失败抛出。"""
    if not needs_catalog_enrich(row):
        return bool((row.description or "").strip())

    name = (row.name or "").strip()
    try:
        summary = await with_retries(
            lambda: fetch_summary_for_species(name, en_name_for(name)),
            max_attempts=4,
            base_sleep=2.0,
        )
    except WikiFetchError:
        # 不写 miss，下次可重试
        raise

    return apply_wiki_summary(db, row, summary)


def apply_wiki_summary(
    db: Session,
    row: CatalogSpecies,
    summary: WikiSummary | None,
    *,
    commit: bool = True,
) -> bool:
    """把摘要写回行；summary is None → 仅在缺简介时记 miss。"""
    now = utcnow()
    had_desc = bool((row.description or "").strip())
    if summary is None:
        if not had_desc:
            row.enrich_status = "miss"
            row.updated_at = now
            db.add(row)
            if commit:
                db.commit()
                db.refresh(row)
        return False

    name = (row.name or "").strip()
    # 中文摘要优先覆盖；英文仅在原先无简介时写入（避免幼崽英文消歧页盖住成体中文）
    if not had_desc:
        row.description = summary.extract
    elif summary.lang == "zh" and _looks_like_weak_description(row.description or ""):
        row.description = summary.extract
    if _looks_like_seed_one_liner(row.one_liner or "", name):
        row.one_liner = one_liner_from_extract(
            (row.description or summary.extract)
        ) or row.one_liner
    if not (row.baike_url or "").strip() and summary.page_url:
        row.baike_url = summary.page_url
    if not (row.image_url or "").strip() and summary.image_url:
        row.image_url = summary.image_url
    row.enrich_status = "ok"
    if (row.source or "") == "seed":
        row.source = "wiki"
    row.updated_at = now
    db.add(row)
    if commit:
        db.commit()
        db.refresh(row)
    logger.info("catalog enrich ok name=%s lang=%s", name, summary.lang)
    return True


async def enrich_catalog_rows_batch(
    db: Session,
    rows: list[CatalogSpecies],
) -> tuple[int, int]:
    """批量补齐。返回 (ok, miss)。临时失败抛 WikiFetchError。"""
    pending = [r for r in rows if needs_catalog_enrich(r)]
    if not pending:
        return 0, 0
    items = [(r.name.strip(), en_name_for(r.name.strip())) for r in pending]
    summaries = await with_retries(
        lambda: fetch_summaries_for_species_batch(items),
        max_attempts=5,
        base_sleep=3.0,
    )
    ok = miss = 0
    for row in pending:
        name = row.name.strip()
        if apply_wiki_summary(db, row, summaries.get(name), commit=False):
            ok += 1
        else:
            miss += 1
    db.commit()
    return ok, miss


def iter_rows_needing_enrich(
    db: Session,
    *,
    limit: int = 0,
    common_only: bool = False,
) -> list[CatalogSpecies]:
    """待补齐行：缺简介（未 miss）或缺配图。"""
    stmt = select(CatalogSpecies)
    if common_only:
        stmt = stmt.where(CatalogSpecies.is_common == 1)
    rows = list(db.scalars(stmt.order_by(CatalogSpecies.id)).all())
    pending = [r for r in rows if needs_catalog_enrich(r)]
    if limit > 0:
        return pending[:limit]
    return pending
