"""探索配图 URL：upload.wikimedia.org 在国内不可达，改写为维基 FilePath。"""

from __future__ import annotations

import re
from pathlib import Path
from urllib.parse import quote, unquote, urlparse

from app.db.session import media_root

# 国内可访问：Special:FilePath 由维基跳转到可达节点
_FILEPATH = "https://zh.wikipedia.org/wiki/Special:FilePath/{file}?width={width}"


def catalog_image_dir() -> Path:
    d = media_root() / "catalog_images"
    d.mkdir(parents=True, exist_ok=True)
    return d


def local_image_path(species_id: int) -> Path:
    return catalog_image_dir() / f"{int(species_id)}.jpg"


def is_wikimedia_image_url(url: str) -> bool:
    u = (url or "").strip().lower()
    if not u:
        return False
    if "upload.wikimedia.org" in u:
        return True
    if "special:filepath" in u:
        return True
    return False


def strip_utm(url: str) -> str:
    return (url or "").strip().split("?", 1)[0]


def commons_filename_from_url(url: str) -> str:
    """从 commons / upload 链接解析文件名。"""
    clean = strip_utm(url)
    path = unquote(urlparse(clean).path)
    parts = [p for p in path.split("/") if p]
    if not parts:
        return ""
    if "thumb" in parts:
        i = parts.index("thumb")
        # /wikipedia/commons/thumb/a/ab/File.jpg/500px-File.jpg
        if i + 3 < len(parts):
            return parts[i + 3]
    # /wikipedia/commons/a/ab/File.jpg 或已是 FilePath
    name = parts[-1]
    # 去掉 500px- 前缀（若误取到 thumb 末段）
    m = re.match(r"^\d+px-(.+)$", name)
    if m:
        return m.group(1)
    return name


def wikimedia_via_filepath(url: str, *, width: int = 500) -> str:
    """维基图床 → Special:FilePath（国内可加载）。"""
    if "special:filepath" in (url or "").lower():
        # 已是 FilePath，统一补 width
        base = strip_utm(url)
        w = max(64, min(int(width), 1200))
        return f"{base}?width={w}"
    filename = commons_filename_from_url(url)
    if not filename:
        return strip_utm(url)
    w = max(64, min(int(width), 1200))
    return _FILEPATH.format(file=quote(filename, safe=""), width=w)


# 兼容旧名
def wikimedia_via_weserv(url: str, *, width: int = 500) -> str:
    return wikimedia_via_filepath(url, width=width)


def public_image_url(
    raw: str,
    *,
    species_id: int | None = None,
    public_base: str = "",
) -> str:
    """对外配图：优先本地 /media/catalog_images；维基→FilePath；其它原样。"""
    raw = (raw or "").strip()
    if species_id is not None:
        path = local_image_path(species_id)
        if path.is_file() and path.stat().st_size > 0:
            base = (public_base or "").rstrip("/")
            rel = f"/media/catalog_images/{int(species_id)}.jpg"
            return f"{base}{rel}" if base else rel
    if is_wikimedia_image_url(raw):
        return wikimedia_via_filepath(raw)
    return raw
