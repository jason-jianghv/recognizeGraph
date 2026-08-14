#!/usr/bin/env python3
"""把 catalog 维基配图拉到本地 data/catalog_images/{id}.jpg。

国内直连 upload.wikimedia.org 常不通；用 Special:FilePath + UA 拉取后缓存。
App 只请求本机 /media/catalog_images/，不依赖外网图床。

用法（server 目录）:
  PYTHONUNBUFFERED=1 python -u ../scripts/cache_catalog_images.py --common-only
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))

from app.db.session import SessionLocal, init_db  # noqa: E402
from app.db.models import CatalogSpecies  # noqa: E402
from app.services.image_url import (  # noqa: E402
    is_wikimedia_image_url,
    local_image_path,
    strip_utm,
    wikimedia_via_filepath,
)
from sqlalchemy import select  # noqa: E402

_UA = "ShituKidsApp/0.2 (catalog-image-cache; local-dev)"


def fetch_bytes(url: str, client: httpx.Client) -> bytes | None:
    try:
        r = client.get(url, timeout=45.0)
        if r.status_code == 429:
            return None  # 调用方退避重试
        if r.status_code != 200:
            return None
        data = r.content
        if len(data) < 200:
            return None
        ctype = (r.headers.get("content-type") or "").lower()
        if "text/html" in ctype:
            return None
        if data[:3] == b"\xff\xd8\xff":
            return data
        if data[:8] == b"\x89PNG\r\n\x1a\n":
            return data
        if data[:4] == b"RIFF" and b"WEBP" in data[:16]:
            return data
        if "image/" in ctype and "json" not in ctype:
            return data
        return None
    except Exception:  # noqa: BLE001
        return None


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--common-only", action="store_true", default=True)
    p.add_argument("--all", action="store_true")
    p.add_argument("--limit", type=int, default=0)
    p.add_argument("--sleep", type=float, default=0.3)
    p.add_argument("--force", action="store_true", help="已有本地文件也重下")
    args = p.parse_args()
    common_only = not args.all

    init_db()
    db = SessionLocal()
    try:
        stmt = select(CatalogSpecies)
        if common_only:
            stmt = stmt.where(CatalogSpecies.is_common == 1)
        rows = list(db.scalars(stmt.order_by(CatalogSpecies.id)).all())
        if args.limit > 0:
            rows = rows[: args.limit]

        ok = skip = fail = 0
        print(f"to_cache={len(rows)} common_only={common_only}", flush=True)
        with httpx.Client(
            headers={"User-Agent": _UA, "Accept": "image/*"},
            follow_redirects=True,
        ) as client:
            for i, row in enumerate(rows, 1):
                path = local_image_path(row.id)
                if path.is_file() and path.stat().st_size > 0 and not args.force:
                    skip += 1
                    continue
                raw = strip_utm(row.image_url or "")
                if not raw:
                    fail += 1
                    print(f"[{i}/{len(rows)}] {row.name} FAIL empty url", flush=True)
                    continue
                if is_wikimedia_image_url(raw):
                    fetch_url = wikimedia_via_filepath(raw, width=600)
                else:
                    fetch_url = raw
                data = fetch_bytes(fetch_url, client)
                if not data and is_wikimedia_image_url(raw):
                    for wait in (3.0, 8.0, 15.0):
                        time.sleep(wait)
                        data = fetch_bytes(fetch_url, client)
                        if data:
                            break
                    if not data:
                        # wsrv 兜底
                        from urllib.parse import quote

                        hostpath = raw.replace("https://", "").replace("http://", "")
                        wsrv = (
                            f"https://wsrv.nl/?url={quote(hostpath, safe='/')}"
                            f"&w=500&output=jpg"
                        )
                        data = fetch_bytes(wsrv, client)
                if not data:
                    fail += 1
                    print(f"[{i}/{len(rows)}] {row.name} FAIL fetch", flush=True)
                    continue
                path.write_bytes(data)
                ok += 1
                print(
                    f"[{i}/{len(rows)}] {row.name} ok {len(data)}B → {path.name}",
                    flush=True,
                )
                if args.sleep > 0:
                    time.sleep(args.sleep)
        print(f"done ok={ok} skip={skip} fail={fail}", flush=True)
    finally:
        db.close()


if __name__ == "__main__":
    main()
