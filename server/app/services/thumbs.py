from __future__ import annotations

import uuid
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image

from app.db.session import media_root

_MAX_SIDE = 480
_JPEG_QUALITY = 82


def save_user_thumb(user_id: int, raw: bytes) -> str:
    """压缩用户图为 JPEG 缩略图，返回相对路径 thumbs/{uid}/{uuid}.jpg。"""
    if not raw:
        return ""
    root = media_root() / "thumbs" / str(user_id)
    root.mkdir(parents=True, exist_ok=True)
    name = f"{uuid.uuid4().hex}.jpg"
    dest = root / name

    from io import BytesIO

    with Image.open(BytesIO(raw)) as im:
        im = im.convert("RGB")
        im.thumbnail((_MAX_SIDE, _MAX_SIDE), Image.Resampling.LANCZOS)
        im.save(dest, format="JPEG", quality=_JPEG_QUALITY, optimize=True)

    return f"thumbs/{user_id}/{name}"


def thumb_public_url(relpath: str) -> str:
    if not relpath:
        return ""
    return f"/media/{relpath.lstrip('/')}"


def year_month_now() -> str:
    try:
        from zoneinfo import ZoneInfo

        return datetime.now(ZoneInfo("Asia/Shanghai")).strftime("%Y-%m")
    except Exception:  # noqa: BLE001
        return datetime.now(timezone.utc).strftime("%Y-%m")
