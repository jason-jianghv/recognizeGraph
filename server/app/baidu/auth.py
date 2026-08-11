"""Baidu OAuth access_token helper with simple in-memory cache."""

from __future__ import annotations

import time
from typing import Optional

import httpx

from app.config import get_settings

TOKEN_URL = "https://aip.baidubce.com/oauth/2.0/token"

_cached_token: Optional[str] = None
_expires_at: float = 0.0


class BaiduAuthError(Exception):
    pass


async def get_access_token(force_refresh: bool = False) -> str:
    """Return a valid Baidu access_token (refresh ~1 day ahead of expiry)."""
    global _cached_token, _expires_at

    settings = get_settings()
    if not settings.baidu_api_key or not settings.baidu_secret_key:
        raise BaiduAuthError(
            "未配置 BAIDU_API_KEY / BAIDU_SECRET_KEY，请复制 server/.env.example 为 server/.env 并填写。"
        )

    now = time.time()
    if (
        not force_refresh
        and _cached_token
        and now < _expires_at - 60
    ):
        return _cached_token

    params = {
        "grant_type": "client_credentials",
        "client_id": settings.baidu_api_key,
        "client_secret": settings.baidu_secret_key,
    }

    async with httpx.AsyncClient(timeout=15.0, trust_env=False) as client:
        resp = await client.post(TOKEN_URL, params=params)
        data = resp.json()

    if "access_token" not in data:
        raise BaiduAuthError(
            f"获取 access_token 失败: {data.get('error_description') or data}"
        )

    _cached_token = data["access_token"]
    # Baidu typically returns expires_in ≈ 2592000 (30 days)
    expires_in = int(data.get("expires_in", 2592000))
    _expires_at = now + expires_in
    return _cached_token
