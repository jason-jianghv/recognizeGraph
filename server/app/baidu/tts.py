"""百度短文本在线合成（非流式）：超限按 GBK 分段，再拼接为一条 MP3。"""

from __future__ import annotations

import json
import re
from typing import List, Optional
from urllib.parse import quote

import httpx

from app.baidu.auth import BaiduAuthError, get_access_token

TTS_URL = "https://tsn.baidu.com/text2audio"

# 官方硬上限 1024 GBK 字节；实测过长易 501，按约 200 汉字留余量分段
MAX_CHUNK_GBK = 400

# 儿童向默认音色参数（可被 voice_profile 覆盖）
DEFAULT_PER = 110  # 度小童
DEFAULT_SPD = 3
DEFAULT_PIT = 5
DEFAULT_VOL = 5
CUID = "shitu-app"

# A=小朋友活泼偏慢；B=男老师；C=女老师（音量/音调均为中等 5）
VOICE_PROFILES = {
    "a": {"per": 110, "spd": 3, "pit": 5, "vol": 5, "emo": "happy"},  # 度小童
    "b": {"per": 106, "spd": 5, "pit": 5, "vol": 5, "emo": None},  # 度博文
    "c": {"per": 0, "spd": 5, "pit": 5, "vol": 5, "emo": None},  # 度小美
}


def resolve_voice_profile(profile: str) -> dict:
    key = (profile or "a").strip().lower()
    return dict(VOICE_PROFILES.get(key) or VOICE_PROFILES["a"])



class BaiduTtsError(Exception):
    pass


def _gbk_len(text: str) -> int:
    return len(text.encode("gbk", errors="ignore"))


def split_text_for_short_tts(text: str, max_gbk: int = MAX_CHUNK_GBK) -> List[str]:
    """按标点优先拆段，每段 GBK 长度不超过 max_gbk。"""
    raw = (text or "").strip()
    if not raw:
        return []
    if _gbk_len(raw) <= max_gbk:
        return [raw]

    # 先按强/弱标点切开，保留分隔符挂在前一段
    parts = re.split(r"(?<=[。！？!?；;…])", raw)
    chunks: List[str] = []
    buf = ""

    def flush() -> None:
        nonlocal buf
        s = buf.strip()
        if s:
            chunks.append(s)
        buf = ""

    for part in parts:
        if not part:
            continue
        candidate = buf + part
        if _gbk_len(candidate) <= max_gbk:
            buf = candidate
            continue
        if buf.strip():
            flush()
        # 单段仍超长：再按逗号拆，最后按字硬切
        if _gbk_len(part) <= max_gbk:
            buf = part
            continue
        sub_parts = re.split(r"(?<=[，,、])", part)
        for sp in sub_parts:
            if not sp:
                continue
            cand2 = buf + sp
            if _gbk_len(cand2) <= max_gbk:
                buf = cand2
                continue
            if buf.strip():
                flush()
            if _gbk_len(sp) <= max_gbk:
                buf = sp
                continue
            # 硬切
            acc = ""
            for ch in sp:
                trial = acc + ch
                if _gbk_len(trial) <= max_gbk:
                    acc = trial
                else:
                    if acc:
                        chunks.append(acc)
                    acc = ch
            buf = acc
    flush()
    return chunks or [raw[: max(1, max_gbk // 2)]]


async def _synthesize_chunk(
    client: httpx.AsyncClient,
    token: str,
    text: str,
    *,
    per: int,
    spd: int,
    pit: int,
    vol: int,
    emo: Optional[str] = None,
) -> bytes:
    # httpx 表单还会再 encode 一次；这里只做 1 次，合计 2 次（与百度文档一致）
    # 若再 quote 两次会导致超长/特殊文本出现 err_no=501 parameter error
    tex = quote(text, safe="")
    data = {
        "tex": tex,
        "tok": token,
        "cuid": CUID,
        "ctp": "1",
        "lan": "zh",
        "spd": str(spd),
        "pit": str(pit),
        "vol": str(vol),
        "per": str(per),
        "aue": "3",  # mp3
    }
    if emo:
        data["text_ctrl"] = json.dumps({"emo": emo}, ensure_ascii=False)
    resp = await client.post(
        TTS_URL,
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    ctype = (resp.headers.get("Content-Type") or "").lower()
    body = resp.content
    if "audio" in ctype:
        if not body:
            raise BaiduTtsError("合成成功但音频为空")
        return body

    # 失败时多为 JSON
    try:
        err = resp.json()
    except Exception:  # noqa: BLE001
        raise BaiduTtsError(f"语音合成失败：HTTP {resp.status_code}") from None
    raise BaiduTtsError(
        f"语音合成失败：{err.get('err_msg') or err} (err_no={err.get('err_no')})"
    )


async def synthesize_mp3(
    text: str,
    *,
    per: int = DEFAULT_PER,
    spd: int = DEFAULT_SPD,
    pit: int = DEFAULT_PIT,
    vol: int = DEFAULT_VOL,
    emo: Optional[str] = None,
) -> bytes:
    """短文本实时非流式合成；超限分段后按字节拼接为一条 MP3。"""
    chunks = split_text_for_short_tts(text)
    if not chunks:
        raise BaiduTtsError("没有可播报的文字")

    token = await get_access_token()
    audio_parts: List[bytes] = []

    async with httpx.AsyncClient(timeout=30.0, trust_env=False) as client:
        for i, chunk in enumerate(chunks):
            try:
                part = await _synthesize_chunk(
                    client,
                    token,
                    chunk,
                    per=per,
                    spd=spd,
                    pit=pit,
                    vol=vol,
                    emo=emo,
                )
            except BaiduTtsError as e:
                msg = str(e).lower()
                # 部分音色不支持情感 / 或返回笼统 parameter error：去掉 emo 再试
                if emo and (
                    "emo" in msg
                    or "text_ctrl" in msg
                    or "notsupport" in msg
                    or "parameter error" in msg
                    or "err_no=501" in msg
                ):
                    part = await _synthesize_chunk(
                        client,
                        token,
                        chunk,
                        per=per,
                        spd=spd,
                        pit=pit,
                        vol=vol,
                        emo=None,
                    )
                elif "token" in msg or "110" in msg or "100" in msg:
                    token = await get_access_token(force_refresh=True)
                    part = await _synthesize_chunk(
                        client,
                        token,
                        chunk,
                        per=per,
                        spd=spd,
                        pit=pit,
                        vol=vol,
                        emo=emo,
                    )
                else:
                    raise BaiduTtsError(f"第 {i + 1}/{len(chunks)} 段合成失败：{e}") from e
            audio_parts.append(part)

    # 同源同参数 MP3 可直接拼接帧
    return b"".join(audio_parts)


def build_speak_script(name: str, one_liner: str) -> str:
    """详情页播报稿：名字 + 简介。"""
    n = (name or "").strip()
    intro = (one_liner or "").strip()
    if n and intro:
        if intro.startswith(n):
            return intro
        return f"{n}。{intro}"
    return n or intro
