from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime, timezone
from pathlib import Path

from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.baidu.auth import BaiduAuthError
from app.baidu.recognize import Category, RecognizeResponse, recognize_image
from app.db.session import get_db
from app.services.catalog import upsert_recognize_candidates

router = APIRouter(prefix="/v1", tags=["recognize"])

MAX_UPLOAD_BYTES = 8 * 1024 * 1024  # soft limit before base64 check
DATA_DIR = Path(__file__).resolve().parents[2] / "data"
FEEDBACK_LOG = DATA_DIR / "feedback.jsonl"
FEEDBACK_IMAGES = DATA_DIR / "feedback_images"

logger = logging.getLogger("shitu")


class FeedbackResponse(BaseModel):
    ok: bool = True
    feedback_id: str
    message: str = "谢谢反馈，我们会让识图变得更准～"


@router.post("/recognize", response_model=RecognizeResponse)
async def recognize(
    category: Category = Form(..., description="animal | plant | transport"),
    image: UploadFile = File(..., description="任意图片，服务端会转为 JPG 再调百度"),
    db: Session = Depends(get_db),
) -> RecognizeResponse:
    data = await image.read()
    if not data:
        raise HTTPException(status_code=400, detail="未收到图片内容")
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=400, detail="上传图片过大，请压缩后重试")

    try:
        result = await recognize_image(category, data)
    except BaiduAuthError as e:
        raise HTTPException(status_code=500, detail=str(e)) from e
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except RuntimeError as e:
        raise HTTPException(status_code=502, detail=str(e)) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=f"识别服务异常: {e}") from e

    # 任意可信度候选都回填全局目录（唯一 category+name）；失败不影响识别响应
    if result.candidates:
        n = upsert_recognize_candidates(db, result.category, result.candidates)
        if n:
            logger.info(
                "catalog upserted %s rows category=%s", n, result.category.value
            )
    return result


@router.post("/feedback", response_model=FeedbackResponse)
async def feedback(
    category: Category = Form(..., description="识别时选的分类"),
    reason: str = Form("none_of_above", description="反馈原因，默认以上都不是"),
    candidate_names: str = Form(
        "",
        description="本次展示过的候选名称，逗号分隔或 JSON 数组字符串",
    ),
    candidate_ids: str = Form("", description="候选 id，逗号分隔或 JSON 数组字符串"),
    note: str = Form("", description="可选补充说明"),
    image: Optional[UploadFile] = File(
        None, description="可选：用户原图，便于复盘误识别"
    ),
) -> FeedbackResponse:
    """「以上都不是」等识别反馈入口，写入本地 jsonl，后续可接标注/训练。"""
    feedback_id = uuid.uuid4().hex[:12]
    names = _parse_list_field(candidate_names)
    ids = _parse_list_field(candidate_ids)

    image_saved = ""
    if image is not None:
        raw = await image.read()
        if raw:
            if len(raw) > MAX_UPLOAD_BYTES:
                raise HTTPException(status_code=400, detail="反馈图片过大")
            FEEDBACK_IMAGES.mkdir(parents=True, exist_ok=True)
            ext = Path(image.filename or "shot.jpg").suffix.lower() or ".jpg"
            if ext not in {".jpg", ".jpeg", ".png", ".webp", ".heic"}:
                ext = ".jpg"
            path = FEEDBACK_IMAGES / f"{feedback_id}{ext}"
            path.write_bytes(raw)
            image_saved = str(path.name)

    record = {
        "id": feedback_id,
        "ts": datetime.now(timezone.utc).isoformat(),
        "category": category.value,
        "reason": reason.strip() or "none_of_above",
        "candidate_names": names,
        "candidate_ids": ids,
        "note": note.strip(),
        "image": image_saved,
    }

    try:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        with FEEDBACK_LOG.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
    except OSError as e:
        logger.exception("write feedback failed")
        raise HTTPException(status_code=500, detail=f"反馈写入失败: {e}") from e

    logger.info(
        "feedback %s category=%s reason=%s names=%s",
        feedback_id,
        category.value,
        record["reason"],
        names,
    )
    return FeedbackResponse(feedback_id=feedback_id)


def _parse_list_field(raw: str) -> list[str]:
    text = (raw or "").strip()
    if not text:
        return []
    if text.startswith("["):
        try:
            data = json.loads(text)
            if isinstance(data, list):
                return [str(x).strip() for x in data if str(x).strip()]
        except json.JSONDecodeError:
            pass
    return [p.strip() for p in text.split(",") if p.strip()]
