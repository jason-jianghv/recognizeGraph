"""Normalize uploads into Baidu-accepted JPEG bytes."""

from __future__ import annotations

import io

from PIL import Image, UnidentifiedImageError

try:
    from pillow_heif import register_heif_opener

    register_heif_opener()
except Exception:  # noqa: BLE001
    # HEIC optional; JPG/PNG still work without it
    pass

# Baidu image-classify accepts PNG / JPG / JPEG / BMP.
# iPhone HEIC / WebP / GIF often trigger error 216201.


def to_baidu_jpeg(image_bytes: bytes, max_side: int = 2048) -> bytes:
    if not image_bytes:
        raise ValueError("图片为空")

    try:
        img = Image.open(io.BytesIO(image_bytes))
        img.load()
    except UnidentifiedImageError as e:
        raise ValueError(
            "无法识别图片格式。请使用 JPG/PNG，或把 iPhone 照片改为「兼容性最好」后再试。"
        ) from e

    if img.mode in ("RGBA", "LA", "P"):
        rgba = img.convert("RGBA")
        background = Image.new("RGB", rgba.size, (255, 255, 255))
        background.paste(rgba, mask=rgba.split()[-1])
        img = background
    elif img.mode != "RGB":
        img = img.convert("RGB")

    w, h = img.size
    longest = max(w, h)
    if longest > max_side:
        scale = max_side / float(longest)
        img = img.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.Resampling.LANCZOS)

    out = io.BytesIO()
    img.save(out, format="JPEG", quality=90, optimize=True)
    data = out.getvalue()
    if not data:
        raise ValueError("图片转换失败")
    return data
