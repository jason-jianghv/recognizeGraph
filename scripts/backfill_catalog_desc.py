#!/usr/bin/env python3
"""批量用维基百科摘要补齐 catalog_species 简介与配图。

优先成功率：MediaWiki 批量查询（少请求）+ 429/500 指数退避重试。

用法（在 server 目录、已激活 venv）:
  PYTHONUNBUFFERED=1 python -u ../scripts/backfill_catalog_desc.py --common-only
  PYTHONUNBUFFERED=1 python -u ../scripts/backfill_catalog_desc.py --batch 20 --sleep 1.5
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))

from app.db.session import SessionLocal, init_db  # noqa: E402
from app.services.catalog_enrich import (  # noqa: E402
    enrich_catalog_rows_batch,
    iter_rows_needing_enrich,
)
from app.services.wiki_summary import WikiFetchError  # noqa: E402


async def run(
    limit: int,
    batch_size: int,
    sleep_s: float,
    *,
    common_only: bool,
) -> None:
    init_db()
    db = SessionLocal()
    try:
        rows = iter_rows_needing_enrich(
            db, limit=limit, common_only=common_only
        )
        ok = miss = failed_batches = 0
        total = len(rows)
        scope = "common_only" if common_only else "all"
        print(
            f"scope={scope} to_enrich={total} batch={batch_size} sleep={sleep_s}",
            flush=True,
        )
        for start in range(0, total, batch_size):
            chunk = rows[start : start + batch_size]
            n = start + len(chunk)
            names = ",".join(r.name for r in chunk[:3])
            try:
                o, m = await enrich_catalog_rows_batch(db, chunk)
                ok += o
                miss += m
                print(
                    f"[{n}/{total}] batch ok={o} miss={m} e.g. {names}",
                    flush=True,
                )
            except WikiFetchError as e:
                failed_batches += 1
                print(
                    f"[{n}/{total}] batch FAILED after retries: {e} (skip batch, leave for next run)",
                    flush=True,
                )
                try:
                    db.rollback()
                except Exception:  # noqa: BLE001
                    pass
            if sleep_s > 0 and n < total:
                await asyncio.sleep(sleep_s)
        print(
            f"done ok={ok} miss={miss} failed_batches={failed_batches}",
            flush=True,
        )
    finally:
        db.close()


def main() -> None:
    p = argparse.ArgumentParser(
        description="Backfill catalog descriptions/images via Wikipedia"
    )
    p.add_argument("--limit", type=int, default=0, help="0 = all needing enrich")
    p.add_argument(
        "--batch",
        type=int,
        default=20,
        help="titles per MediaWiki request (default 20)",
    )
    p.add_argument(
        "--sleep",
        type=float,
        default=1.5,
        help="seconds between batches (default 1.5)",
    )
    p.add_argument(
        "--common-only",
        action="store_true",
        help="只补 is_common=1（探索常规名单）",
    )
    p.add_argument(
        "--all",
        action="store_true",
        help="补全库（含生僻）；与 --common-only 互斥，默认 common-only",
    )
    args = p.parse_args()
    batch = max(1, min(args.batch, 40))
    # 默认只跑常规；显式 --all 才全量
    common_only = not args.all
    if args.common_only:
        common_only = True
    asyncio.run(run(args.limit, batch, args.sleep, common_only=common_only))


if __name__ == "__main__":
    main()
