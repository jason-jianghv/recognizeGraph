"""中文名 → 英文名：本地词表优先，百度机器翻译兜底；机翻成功后写入本地学习词表。"""

from __future__ import annotations

import json
import logging
import re
import threading
from pathlib import Path
from typing import Dict, Optional, Tuple

from app.baidu.translate import BaiduTranslateError, translate_zh_to_en

logger = logging.getLogger("shitu.name_en")

_SERVER_DIR = Path(__file__).resolve().parents[2]
_RESOURCES = _SERVER_DIR / "resources" / "name_en"
_MAP_PATH = _RESOURCES / "zh_en_map.json"
# 可写目录（server/data 已 gitignore）：机翻回填，避免重复调翻译 API
_LEARNED_PATH = _SERVER_DIR / "data" / "name_en" / "zh_en_learned.json"

_lock = threading.Lock()
_base_map: Optional[Dict[str, str]] = None
_learned_map: Optional[Dict[str, str]] = None


class NameEnResult(dict):
    """便于 JSON 序列化的结果。"""

    @property
    def name_zh(self) -> str:
        return str(self.get("name_zh") or "")

    @property
    def name_en(self) -> str:
        return str(self.get("name_en") or "")

    @property
    def source(self) -> str:
        return str(self.get("source") or "")


def _read_json_map(path: Path) -> Dict[str, str]:
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        logger.warning("failed to read %s: %s", path, e)
        return {}
    if not isinstance(data, dict):
        return {}
    return {
        str(k).strip(): str(v).strip()
        for k, v in data.items()
        if str(k).strip() and str(v).strip()
    }


def _ensure_maps_loaded() -> None:
    global _base_map, _learned_map
    with _lock:
        if _base_map is None:
            if not _MAP_PATH.is_file():
                logger.warning("name_en map missing: %s", _MAP_PATH)
                _base_map = {}
            else:
                _base_map = _read_json_map(_MAP_PATH)
                logger.info("loaded name_en base map: %s entries", len(_base_map))
        if _learned_map is None:
            _learned_map = _read_json_map(_LEARNED_PATH)
            if _learned_map:
                logger.info(
                    "loaded name_en learned map: %s entries from %s",
                    len(_learned_map),
                    _LEARNED_PATH,
                )


def _merged_map() -> Dict[str, str]:
    _ensure_maps_loaded()
    assert _base_map is not None and _learned_map is not None
    # 学习词表覆盖同名（机翻回填）
    return {**_base_map, **_learned_map}


def _persist_learned(zh: str, en: str) -> None:
    """把机翻结果写入本地学习词表，供下次直接命中。"""
    global _learned_map
    _ensure_maps_loaded()
    assert _learned_map is not None
    with _lock:
        if _learned_map.get(zh) == en:
            return
        _learned_map[zh] = en
        _LEARNED_PATH.parent.mkdir(parents=True, exist_ok=True)
        # 整表重写：量级通常远小于基础词表
        tmp = _LEARNED_PATH.with_suffix(".json.tmp")
        tmp.write_text(
            json.dumps(_learned_map, ensure_ascii=False, indent=1, sort_keys=True),
            encoding="utf-8",
        )
        tmp.replace(_LEARNED_PATH)
        logger.info("name_en learned saved: %s → %s", zh, en)


def load_zh_en_map() -> Dict[str, str]:
    """供调试/测试：基础词表 + 学习词表。"""
    return _merged_map()


def _normalize_zh(name: str) -> str:
    s = (name or "").strip()
    s = re.sub(r"\s+", "", s)
    s = s.strip("《》【】（）()「」""\"'")
    return s


def _lookup_variants(zh: str) -> Tuple[str, Optional[str], str]:
    """返回 (命中用的中文 key, 英文, source)。source: lexicon | learned | none。"""
    _ensure_maps_loaded()
    assert _base_map is not None and _learned_map is not None
    if not zh:
        return zh, None, "none"

    def hit(key: str) -> Optional[Tuple[str, str, str]]:
        if key in _learned_map:
            return key, _learned_map[key], "learned"
        if key in _base_map:
            return key, _base_map[key], "lexicon"
        return None

    for key in (zh,):
        found = hit(key)
        if found:
            return found

    # 小兔子 → 兔子；兔子 → 小兔子
    if zh.startswith("小") and len(zh) >= 3:
        found = hit(zh[1:])
        if found:
            return found
    found = hit(f"小{zh}")
    if found:
        return found

    for suf in ("花", "树", "鱼", "草"):
        if zh.endswith(suf) and len(zh) > len(suf) + 1:
            found = hit(zh[: -len(suf)])
            if found:
                return found

    return zh, None, "none"


def build_bilingual_speak_script(name_zh: str, name_en: str) -> str:
    zh = _normalize_zh(name_zh)
    en = (name_en or "").strip()
    if zh and en:
        return f"{zh}。{en}。"
    return f"{zh}。" if zh else (f"{en}。" if en else "")


async def resolve_name_en(name_zh: str, *, allow_translate: bool = True) -> NameEnResult:
    """词表/学习词表命中 → 直接返回；否则机翻并回填学习词表。"""
    zh = _normalize_zh(name_zh)
    if not zh:
        return NameEnResult(name_zh="", name_en="", source="empty", speak="")

    _, en, src = _lookup_variants(zh)
    if en:
        return NameEnResult(
            name_zh=zh,
            name_en=en,
            source=src,
            speak=build_bilingual_speak_script(zh, en),
        )

    if not allow_translate:
        return NameEnResult(
            name_zh=zh,
            name_en="",
            source="none",
            speak=build_bilingual_speak_script(zh, ""),
        )

    try:
        en = await translate_zh_to_en(zh)
        en = (en or "").strip()
        if len(en) > 48:
            en = en[:48].rstrip()
        if en:
            try:
                _persist_learned(zh, en)
            except Exception as e:  # noqa: BLE001
                logger.warning("persist learned failed for %s: %s", zh, e)
            return NameEnResult(
                name_zh=zh,
                name_en=en,
                source="translate",
                speak=build_bilingual_speak_script(zh, en),
            )
    except BaiduTranslateError as e:
        logger.info("translate miss for %s: %s", zh, e)
    except Exception as e:  # noqa: BLE001
        logger.info("translate error for %s: %s", zh, e)

    return NameEnResult(
        name_zh=zh,
        name_en="",
        source="none",
        speak=build_bilingual_speak_script(zh, ""),
    )
