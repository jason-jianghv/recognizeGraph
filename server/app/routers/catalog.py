"""物种目录 API：供探索/更多后续接真数据；当前可由识别回填。"""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import desc, func, select
from sqlalchemy.orm import Session

from app.baidu.recognize import Category
from app.db.models import CatalogSpecies
from app.db.session import get_db
from app.services.catalog_enrich import enrich_catalog_row, needs_description_enrich
from app.services.image_url import public_image_url

router = APIRouter(prefix="/v1/catalog", tags=["catalog"])


class CatalogItem(BaseModel):
    id: int
    category: str
    name: str
    candidate_id: str = ""
    one_liner: str = ""
    description: str = ""
    baike_url: str = ""
    image_url: str = ""
    last_score: float = 0.0
    best_score: float = 0.0
    seen_count: int = 1
    source: str = "recognize"
    enrich_status: str = ""
    is_common: bool = True
    updated_at: str = ""


class CatalogPage(BaseModel):
    category: str
    page: int
    page_size: int
    total: int
    items: list[CatalogItem] = Field(default_factory=list)


def _public_base(request: Request) -> str:
    # 真机访问局域网 IP 时，用请求 Host 拼绝对图链
    return str(request.base_url).rstrip("/")


def _item(row: CatalogSpecies, *, public_base: str = "") -> CatalogItem:
    return CatalogItem(
        id=row.id,
        category=row.category,
        name=row.name,
        candidate_id=row.candidate_id or "",
        one_liner=row.one_liner or "",
        description=row.description or "",
        baike_url=row.baike_url or "",
        image_url=public_image_url(
            row.image_url or "",
            species_id=row.id,
            public_base=public_base,
        ),
        last_score=float(row.last_score or 0),
        best_score=float(row.best_score or 0),
        seen_count=int(row.seen_count or 1),
        source=row.source or "recognize",
        enrich_status=row.enrich_status or "",
        is_common=bool(int(row.is_common or 0)),
        updated_at=row.updated_at.isoformat() if row.updated_at else "",
    )


@router.get("", response_model=CatalogPage)
async def list_catalog(
    request: Request,
    category: Category = Query(..., description="animal | plant | transport"),
    page: int = Query(1, ge=1),
    page_size: int = Query(30, ge=1, le=100),
    q: Optional[str] = Query(None, description="可选：名称模糊搜索"),
    common_only: bool = Query(
        True,
        description="默认只返回常规物种（探索用）；false 可含生僻 tropials",
    ),
    db: Session = Depends(get_db),
) -> CatalogPage:
    """按分类列出目录。探索/更多默认 common_only=true。"""
    cat = category.value
    stmt = select(CatalogSpecies).where(CatalogSpecies.category == cat)
    count_stmt = select(func.count()).select_from(CatalogSpecies).where(
        CatalogSpecies.category == cat
    )
    if common_only:
        stmt = stmt.where(CatalogSpecies.is_common == 1)
        count_stmt = count_stmt.where(CatalogSpecies.is_common == 1)
    keyword = (q or "").strip()
    if keyword:
        like = f"%{keyword}%"
        stmt = stmt.where(CatalogSpecies.name.like(like))
        count_stmt = count_stmt.where(CatalogSpecies.name.like(like))

    total = int(db.scalar(count_stmt) or 0)
    rows = db.scalars(
        stmt.order_by(
            desc(CatalogSpecies.seen_count),
            desc(CatalogSpecies.best_score),
            CatalogSpecies.name,
        )
        .offset((page - 1) * page_size)
        .limit(page_size)
    ).all()
    base = _public_base(request)
    return CatalogPage(
        category=cat,
        page=page,
        page_size=page_size,
        total=total,
        items=[_item(r, public_base=base) for r in rows],
    )


@router.get("/{species_id}", response_model=CatalogItem)
async def get_catalog_item(
    request: Request,
    species_id: int,
    enrich: bool = Query(
        True,
        description="缺简介时尝试维基百科补齐并写回数据库",
    ),
    db: Session = Depends(get_db),
) -> CatalogItem:
    row = db.get(CatalogSpecies, species_id)
    if row is None:
        raise HTTPException(status_code=404, detail="目录中没有这条")
    if enrich and needs_description_enrich(row):
        try:
            await enrich_catalog_row(db, row)
        except Exception:  # noqa: BLE001
            # 补齐失败（含限流）不影响返回已有字段；不记 miss
            pass
        row = db.get(CatalogSpecies, species_id) or row
    return _item(row, public_base=_public_base(request))


class EnrichBatchResponse(BaseModel):
    tried: int = 0
    ok: int = 0
    miss: int = 0


@router.post("/enrich/run", response_model=EnrichBatchResponse)
async def enrich_batch(
    limit: int = Query(20, ge=1, le=200, description="本批最多处理条数"),
    db: Session = Depends(get_db),
) -> EnrichBatchResponse:
    """批量补简介（维基）。全量请用 scripts/backfill_catalog_desc.py。"""
    from app.services.catalog_enrich import iter_rows_needing_enrich

    rows = iter_rows_needing_enrich(db, limit=limit)
    ok = miss = 0
    for row in rows:
        try:
            if await enrich_catalog_row(db, row):
                ok += 1
            else:
                miss += 1
        except Exception:  # noqa: BLE001
            miss += 1
    return EnrichBatchResponse(tried=len(rows), ok=ok, miss=miss)
