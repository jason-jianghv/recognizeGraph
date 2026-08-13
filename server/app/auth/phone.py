"""中国大陆手机号校验（MVP；后续可扩区号/白名单）。"""

from __future__ import annotations

import re

# 1 开头，第二位 3–9，共 11 位
_CN_MOBILE = re.compile(r"^1[3-9]\d{9}$")


def normalize_phone(raw: str) -> str:
    return (raw or "").strip().replace(" ", "").replace("-", "")


def is_valid_cn_mobile(phone: str) -> bool:
    return bool(_CN_MOBILE.fullmatch(normalize_phone(phone)))


def require_valid_cn_mobile(phone: str) -> str:
    normalized = normalize_phone(phone)
    if not is_valid_cn_mobile(normalized):
        raise ValueError("手机号格式不正确，请输入 11 位大陆手机号")
    return normalized
