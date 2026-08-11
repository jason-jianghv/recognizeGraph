"""Baidu image recognition API calls + response normalization."""

from __future__ import annotations

import base64
from enum import Enum
from typing import Any

import httpx
from pydantic import BaseModel, Field

from app.baidu.auth import get_access_token
from app.baidu.image_util import to_baidu_jpeg

ANIMAL_URL = "https://aip.baidubce.com/rest/2.0/image-classify/v1/animal"
PLANT_URL = "https://aip.baidubce.com/rest/2.0/image-classify/v1/plant"
GENERAL_URL = "https://aip.baidubce.com/rest/2.0/image-classify/v2/advanced_general"


class Category(str, Enum):
    animal = "animal"
    plant = "plant"
    transport = "transport"  # 交通工具与建筑


class Candidate(BaseModel):
    id: str
    name: str
    score: float = 0.0
    one_liner: str = ""
    baike_url: str = ""
    image_url: str = ""
    description: str = ""


class RecognizeResponse(BaseModel):
    category: Category
    candidates: list[Candidate] = Field(default_factory=list)
    raw_hint: str = ""


def _clean_image_url(url: str) -> str:
    """丢掉空链接和百度占位/品牌 logo；http 升 https，减少客户端加载失败。"""
    text = (url or "").strip()
    if not text:
        return ""
    lower = text.lower()
    junk_markers = (
        "bd_logo",
        "baidu_logo",
        "baidu-logo",
        "logo-baidu",
        "passport.baidu.com",
        "bdstatic.com/static/common",
        "bdstatic.com/img/logo",
        "ss0.bdstatic.com/5ac",
    )
    if any(m in lower for m in junk_markers):
        return ""
    if lower.endswith(("/logo", "/logo/", "favicon.ico")):
        return ""
    # 路径恰好是 /logo.png 这类品牌图；避免误伤百科图路径里的普通文件名
    path = lower.split("?", 1)[0]
    if path.endswith(("/logo.png", "/logo.jpg", "/logo.jpeg", "/logo.webp", "/logo.gif")):
        return ""
    if text.startswith("http://"):
        text = "https://" + text[len("http://") :]
    return text


def _one_liner_from_baike(desc: str, limit: int = 40) -> str:
    text = (desc or "").strip().replace("\n", " ")
    if not text:
        return ""
    if len(text) <= limit:
        return text
    return text[: limit - 1] + "…"


def _normalize_animal_plant(
    category: Category, result: list[dict[str, Any]]
) -> list[Candidate]:
    out: list[Candidate] = []
    for item in result:
        name = str(item.get("name") or "").strip()
        if not name or name in {"非动物", "非植物"}:
            continue
        try:
            score = float(item.get("score") or 0)
        except (TypeError, ValueError):
            score = 0.0
        baike = item.get("baike_info") or {}
        desc = str(baike.get("description") or "")
        out.append(
            Candidate(
                id=f"baidu:{category.value}:{name}",
                name=name,
                score=score,
                one_liner=_one_liner_from_baike(desc) or f"可能是「{name}」",
                baike_url=str(baike.get("baike_url") or ""),
                image_url=_clean_image_url(str(baike.get("image_url") or "")),
                description=desc,
            )
        )
    out.sort(key=lambda c: c.score, reverse=True)
    return out


def _normalize_general(result: list[dict[str, Any]]) -> list[Candidate]:
    out: list[Candidate] = []
    for item in result:
        name = str(item.get("keyword") or item.get("name") or "").strip()
        if not name:
            continue
        try:
            # advanced_general uses score 0~1
            score = float(item.get("score") or 0)
        except (TypeError, ValueError):
            score = 0.0
        root = str(item.get("root") or "")
        baike = item.get("baike_info") or {}
        desc = str(baike.get("description") or "")
        one = _one_liner_from_baike(desc)
        if not one:
            one = f"{root} · {name}" if root else f"可能是「{name}」"
        out.append(
            Candidate(
                id=f"baidu:transport:{name}",
                name=name,
                score=score,
                one_liner=one,
                baike_url=str(baike.get("baike_url") or ""),
                image_url=_clean_image_url(str(baike.get("image_url") or "")),
                description=desc or root,
            )
        )
    out.sort(key=lambda c: c.score, reverse=True)
    return out


async def recognize_image(
    category: Category, image_bytes: bytes, top_num: int = 5
) -> RecognizeResponse:
    if not image_bytes:
        raise ValueError("图片为空")

    # Convert HEIC/WebP/etc. → JPEG so Baidu won't return 216201
    jpeg_bytes = to_baidu_jpeg(image_bytes)
    b64 = base64.b64encode(jpeg_bytes).decode("ascii")
    if len(b64) > 4 * 1024 * 1024:
        raise ValueError("图片过大（base64 超过约 4MB），请压缩后重试")

    token = await get_access_token()
    headers = {"Content-Type": "application/x-www-form-urlencoded"}

    if category == Category.animal:
        url = ANIMAL_URL
        form = {"image": b64, "top_num": top_num, "baike_num": top_num}
    elif category == Category.plant:
        url = PLANT_URL
        form = {"image": b64, "top_num": top_num, "baike_num": top_num}
    else:
        url = GENERAL_URL
        form = {"image": b64, "baike_num": top_num}

    async with httpx.AsyncClient(timeout=30.0, trust_env=False) as client:
        resp = await client.post(
            f"{url}?access_token={token}",
            data=form,
            headers=headers,
        )
        data = resp.json()

    if "error_code" in data:
        raise RuntimeError(
            f"百度识别失败({data.get('error_code')}): {data.get('error_msg')}"
        )

    if category in (Category.animal, Category.plant):
        candidates = _normalize_animal_plant(category, data.get("result") or [])
    else:
        # advanced_general: result is list under "result"
        candidates = _normalize_general(data.get("result") or [])
        candidates = candidates[:top_num]

    return RecognizeResponse(
        category=category,
        candidates=candidates,
        raw_hint="ok" if candidates else "no_result",
    )
