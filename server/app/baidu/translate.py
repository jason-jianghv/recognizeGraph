"""百度智能云文本翻译（通用版）zh → en。"""

from __future__ import annotations

import logging
from typing import Any

import httpx

from app.baidu.auth import BaiduAuthError, get_access_token

logger = logging.getLogger("shitu.translate")

# 文档：https://cloud.baidu.com/doc/MT/s/4kqryjku9
TRANSLATE_URL = "https://aip.baidubce.com/rpc/2.0/mt/texttrans/v1"


class BaiduTranslateError(Exception):
    pass


async def translate_zh_to_en(text: str) -> str:
    q = (text or "").strip()
    if not q:
        return ""

    try:
        token = await get_access_token()
    except BaiduAuthError as e:
        raise BaiduTranslateError(str(e)) from e

    payload: dict[str, Any] = {"q": q, "from": "zh", "to": "en"}
    async with httpx.AsyncClient(timeout=15.0, trust_env=False) as client:
        resp = await client.post(
            TRANSLATE_URL,
            params={"access_token": token},
            json=payload,
            headers={"Content-Type": "application/json"},
        )
        data = resp.json()

    # 成功结构：{"result":{"trans_result":[{"src":"...","dst":"..."}]}}
    if isinstance(data, dict) and data.get("error_code"):
        raise BaiduTranslateError(
            f"翻译失败：{data.get('error_msg') or data} (error_code={data.get('error_code')})"
        )

    result = data.get("result") if isinstance(data, dict) else None
    trans = None
    if isinstance(result, dict):
        trans = result.get("trans_result")
    if not trans and isinstance(data, dict):
        trans = data.get("trans_result")
    if isinstance(trans, list) and trans:
        dst = str(trans[0].get("dst") or "").strip()
        if dst:
            return dst
    raise BaiduTranslateError(f"翻译无结果：{data}")
