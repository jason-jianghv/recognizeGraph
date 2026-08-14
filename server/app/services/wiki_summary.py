"""按中文名拉取维基百科摘要，用于补齐 catalog 简介。"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from typing import Iterable
from urllib.parse import quote

import httpx

logger = logging.getLogger("shitu")

_UA = "ShituKidsApp/0.2 (catalog-enrich; local-dev; contact=dev@localhost)"
# 批量一次不宜过大，兼顾成功率
_BATCH_MAX = 20


@dataclass
class WikiSummary:
    title: str
    extract: str
    page_url: str
    image_url: str
    lang: str


class WikiFetchError(Exception):
    """临时失败（限流/网络），调用方不应记 enrich_status=miss。"""

    def __init__(self, message: str, *, retryable: bool = True):
        super().__init__(message)
        self.retryable = retryable


def _one_liner(desc: str, limit: int = 40) -> str:
    text = (desc or "").strip().replace("\n", " ")
    if not text:
        return ""
    if len(text) <= limit:
        return text
    return text[: limit - 1] + "…"


def one_liner_from_extract(extract: str) -> str:
    return _one_liner(extract)


async def _get_json(
    client: httpx.AsyncClient,
    url: str,
    *,
    params: dict | None = None,
) -> dict:
    try:
        resp = await client.get(url, params=params)
    except httpx.HTTPError as e:
        raise WikiFetchError(f"network: {e}") from e
    if resp.status_code == 429 or resp.status_code >= 500:
        raise WikiFetchError(f"status {resp.status_code}", retryable=True)
    if resp.status_code == 404:
        return {}
    if resp.status_code >= 400:
        logger.info("wiki bad status url=%s code=%s", url, resp.status_code)
        return {}
    try:
        data = resp.json()
    except ValueError as e:
        raise WikiFetchError(f"bad json: {e}") from e
    if not isinstance(data, dict):
        return {}
    return data


async def fetch_wikipedia_summary(
    title: str,
    *,
    lang: str = "zh",
) -> WikiSummary | None:
    """单条：REST summary。限流/5xx 抛 WikiFetchError。"""
    name = (title or "").strip()
    if not name:
        return None
    url = (
        f"https://{lang}.wikipedia.org/api/rest_v1/page/summary/"
        f"{quote(name, safe='')}"
    )
    async with httpx.AsyncClient(
        timeout=20.0,
        headers={"User-Agent": _UA, "Accept": "application/json"},
        follow_redirects=True,
    ) as client:
        data = await _get_json(client, url)
    if not data:
        return None
    kind = str(data.get("type") or "")
    extract = str(data.get("extract") or "").strip()
    if kind == "disambiguation" and not extract:
        return None
    if not extract:
        return None
    content_urls = data.get("content_urls") or {}
    desktop = content_urls.get("desktop") or {}
    page_url = str(desktop.get("page") or "")
    if not page_url:
        page_url = f"https://{lang}.wikipedia.org/wiki/{quote(name)}"
    thumb = data.get("thumbnail") or {}
    image_url = str(thumb.get("source") or "").strip()
    return WikiSummary(
        title=str(data.get("title") or name),
        extract=extract,
        page_url=page_url,
        image_url=image_url,
        lang=lang,
    )


async def fetch_summary_for_species(
    name_zh: str,
    name_en: str = "",
) -> WikiSummary | None:
    """先中文维基，没有再试英文名。临时错误向上抛出。"""
    hit = await fetch_wikipedia_summary(name_zh, lang="zh")
    if hit:
        return hit
    en = (name_en or "").strip()
    if en:
        return await fetch_wikipedia_summary(en, lang="en")
    return None


def _page_to_summary(page: dict, *, lang: str, query_title: str) -> WikiSummary | None:
    if not page or page.get("missing") is not None:
        return None
    extract = str(page.get("extract") or "").strip()
    if not extract:
        return None
    title = str(page.get("title") or query_title).strip() or query_title
    pageid = page.get("pageid")
    if pageid:
        page_url = f"https://{lang}.wikipedia.org/?curid={pageid}"
    else:
        page_url = f"https://{lang}.wikipedia.org/wiki/{quote(title)}"
    thumb = page.get("thumbnail") or {}
    image_url = str(thumb.get("source") or "").strip()
    return WikiSummary(
        title=title,
        extract=extract,
        page_url=page_url,
        image_url=image_url,
        lang=lang,
    )


async def fetch_wikipedia_summaries_batch(
    titles: Iterable[str],
    *,
    lang: str = "zh",
) -> dict[str, WikiSummary | None]:
    """一次请求多条（MediaWiki extracts）。返回 query_title → 摘要或 None。

    限流/5xx 抛 WikiFetchError（整批可退避后重试）。
    """
    cleaned: list[str] = []
    seen: set[str] = set()
    for t in titles:
        name = (t or "").strip()
        if not name or name in seen:
            continue
        seen.add(name)
        cleaned.append(name)
    out: dict[str, WikiSummary | None] = {t: None for t in cleaned}
    if not cleaned:
        return out

    url = f"https://{lang}.wikipedia.org/w/api.php"
    async with httpx.AsyncClient(
        timeout=30.0,
        headers={"User-Agent": _UA, "Accept": "application/json"},
        follow_redirects=True,
    ) as client:
        for i in range(0, len(cleaned), _BATCH_MAX):
            chunk = cleaned[i : i + _BATCH_MAX]
            params = {
                "action": "query",
                "format": "json",
                "formatversion": "2",
                "prop": "extracts|pageimages",
                "exintro": "1",
                "explaintext": "1",
                "piprop": "thumbnail",
                "pithumbsize": "400",
                "redirects": "1",
                "titles": "|".join(chunk),
            }
            data = await _get_json(client, url, params=params)
            query = data.get("query") or {}
            pages = query.get("pages") or []
            redirects = {
                str(r.get("from") or ""): str(r.get("to") or "")
                for r in (query.get("redirects") or [])
                if r.get("from") and r.get("to")
            }
            normalized = {
                str(n.get("from") or ""): str(n.get("to") or "")
                for n in (query.get("normalized") or [])
                if n.get("from") and n.get("to")
            }
            by_title: dict[str, dict] = {}
            for page in pages:
                if not isinstance(page, dict):
                    continue
                t = str(page.get("title") or "").strip()
                if t:
                    by_title[t] = page

            for qtitle in chunk:
                resolved = qtitle
                # normalized / redirects 可能链式
                for _ in range(4):
                    if resolved in normalized:
                        resolved = normalized[resolved]
                        continue
                    if resolved in redirects:
                        resolved = redirects[resolved]
                        continue
                    break
                page = by_title.get(resolved) or by_title.get(qtitle)
                out[qtitle] = _page_to_summary(page or {}, lang=lang, query_title=qtitle)
    return out


# 儿童叠词/幼崽词条常无配图 → 用成体/常见词条补图
_IMAGE_EN_TITLES: dict[str, str] = {
    "小猪": "Pig",
    "小羊": "Sheep",
    "小鸡": "Chicken",
    "小狗": "Dog",
    "小猫": "Cat",
    "小马": "Horse",
    "土豆": "Potato",
    "卡车": "Truck",
    "多肉": "Succulent plant",
}
_IMAGE_ZH_TITLES: dict[str, str] = {
    "小猪": "猪",
    "小羊": "羊",
    "小鸡": "鸡",
    "小狗": "狗",
    "小猫": "猫",
    "小马": "马",
}


def _image_en_title(zh: str, en: str) -> str:
    return _IMAGE_EN_TITLES.get(zh) or (en or "").strip()


def _merge_image(base: WikiSummary, donor: WikiSummary | None) -> WikiSummary:
    if not donor or not (donor.image_url or "").strip():
        return base
    if (base.image_url or "").strip():
        return base
    return WikiSummary(
        title=base.title,
        extract=base.extract,
        page_url=base.page_url,
        image_url=donor.image_url,
        lang=base.lang,
    )


async def fetch_summaries_for_species_batch(
    items: list[tuple[str, str]],
) -> dict[str, WikiSummary | None]:
    """items = [(zh, en), ...]。先中文批量，未命中再用英文名批量。

    中文幼崽名无词条/无配图时：先试成体中文名，再试英文成体词条。
    返回以中文名为 key。
    """
    zh_list = [zh for zh, _ in items if (zh or "").strip()]
    zh_hits = await fetch_wikipedia_summaries_batch(zh_list, lang="zh")
    result: dict[str, WikiSummary | None] = dict(zh_hits)

    need_zh_alt_full: list[tuple[str, str]] = []
    need_en_full: list[tuple[str, str]] = []
    need_zh_image: list[tuple[str, str]] = []
    need_en_image: list[tuple[str, str]] = []
    for zh, en in items:
        zh = (zh or "").strip()
        if not zh:
            continue
        en = (en or "").strip()
        hit = result.get(zh)
        alt_zh = _IMAGE_ZH_TITLES.get(zh)
        en_img = _image_en_title(zh, en)
        if hit is None:
            if alt_zh:
                need_zh_alt_full.append((zh, alt_zh))
            elif en_img:
                need_en_full.append((zh, en_img))
            continue
        if not (hit.image_url or "").strip():
            if alt_zh:
                need_zh_image.append((zh, alt_zh))
            if en_img:
                need_en_image.append((zh, en_img))

    if need_zh_alt_full:
        alt_titles = [alt for _, alt in need_zh_alt_full]
        alt_hits = await fetch_wikipedia_summaries_batch(alt_titles, lang="zh")
        for zh, alt in need_zh_alt_full:
            hit = alt_hits.get(alt)
            if hit is not None:
                result[zh] = hit
            else:
                en_img = _image_en_title(zh, "")
                if en_img:
                    need_en_full.append((zh, en_img))

    if need_en_full:
        en_titles = [en for _, en in need_en_full]
        en_hits = await fetch_wikipedia_summaries_batch(en_titles, lang="en")
        for zh, en in need_en_full:
            if result.get(zh) is None:
                result[zh] = en_hits.get(en)

    if need_zh_image:
        alt_titles = [alt for _, alt in need_zh_image]
        alt_hits = await fetch_wikipedia_summaries_batch(alt_titles, lang="zh")
        for zh, alt in need_zh_image:
            zh_hit = result.get(zh)
            if zh_hit:
                result[zh] = _merge_image(zh_hit, alt_hits.get(alt))

    still_need_en_image = [
        (zh, en)
        for zh, en in need_en_image
        if result.get(zh) and not (result[zh].image_url or "").strip()
    ]
    if still_need_en_image:
        en_titles = [en for _, en in still_need_en_image]
        en_hits = await fetch_wikipedia_summaries_batch(en_titles, lang="en")
        for zh, en in still_need_en_image:
            zh_hit = result.get(zh)
            if zh_hit:
                result[zh] = _merge_image(zh_hit, en_hits.get(en))

    return result


async def with_retries(
    coro_factory,
    *,
    max_attempts: int = 5,
    base_sleep: float = 2.0,
):
    """对 WikiFetchError 指数退避重试，提高成功率。"""
    last: Exception | None = None
    for attempt in range(1, max_attempts + 1):
        try:
            return await coro_factory()
        except WikiFetchError as e:
            last = e
            if not e.retryable or attempt >= max_attempts:
                raise
            wait = min(base_sleep * (2 ** (attempt - 1)), 60.0)
            logger.info(
                "wiki retryable error attempt=%s/%s wait=%.1fs err=%s",
                attempt,
                max_attempts,
                wait,
                e,
            )
            await asyncio.sleep(wait)
    assert last is not None
    raise last
