"""详情页语音：百度短文本 TTS（非流式），返回拼接后的 MP3。"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, Field

from app.baidu.auth import BaiduAuthError
from app.baidu.tts import (
    BaiduTtsError,
    build_speak_script,
    resolve_voice_profile,
    synthesize_mp3,
)

router = APIRouter(prefix="/v1/tts", tags=["tts"])


class TtsRequest(BaseModel):
    name: str = Field("", description="物品名称")
    one_liner: str = Field("", description="简介（详情名称下方那段）")
    text: str = Field("", description="若填写则优先作为完整播报稿")
    voice_profile: str = Field(
        "a",
        description="语音偏好：a=小朋友活泼偏慢 / b=男老师 / c=女老师",
    )


@router.post("")
async def synthesize(req: TtsRequest) -> Response:
    script = (req.text or "").strip()
    if not script:
        script = build_speak_script(req.name, req.one_liner)
    if not script:
        raise HTTPException(status_code=400, detail="没有可播报的文字")

    voice = resolve_voice_profile(req.voice_profile)
    try:
        audio = await synthesize_mp3(
            script,
            per=int(voice["per"]),
            spd=int(voice["spd"]),
            pit=int(voice["pit"]),
            vol=int(voice["vol"]),
            emo=voice.get("emo"),
        )
    except BaiduAuthError as e:
        raise HTTPException(status_code=503, detail=str(e)) from e
    except BaiduTtsError as e:
        raise HTTPException(status_code=502, detail=str(e)) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=502, detail=f"语音合成异常：{e}") from e

    return Response(
        content=audio,
        media_type="audio/mpeg",
        headers={
            "Content-Disposition": 'inline; filename="shitu-tts.mp3"',
            "Cache-Control": "no-store",
            "X-Voice-Profile": (req.voice_profile or "a").strip().lower() or "a",
        },
    )
