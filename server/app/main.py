import logging
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.db.session import init_db, media_root
from app.routers.auth import router as auth_router
from app.routers.catalog import router as catalog_router
from app.routers.history import router as history_router
from app.routers.me import router as me_router
from app.routers.recognize import router as recognize_router
from app.routers.name_en import router as name_en_router
from app.routers.tts import router as tts_router

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("shitu")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    init_db()
    logger.info("DB ready at %s", media_root() / "shitu.db")
    yield


app = FastAPI(
    title="识图 API",
    description="儿童拍照识物后端（百度智能云图像识别）",
    version="0.2.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def log_requests(request: Request, call_next):
    started = time.time()
    client = request.client.host if request.client else "?"
    logger.info("→ %s %s from %s", request.method, request.url.path, client)
    try:
        response = await call_next(request)
    except Exception:
        logger.exception("✗ %s %s crashed", request.method, request.url.path)
        raise
    ms = int((time.time() - started) * 1000)
    logger.info(
        "← %s %s → %s (%sms)",
        request.method,
        request.url.path,
        response.status_code,
        ms,
    )
    return response


app.include_router(recognize_router)
app.include_router(catalog_router)
app.include_router(auth_router)
app.include_router(me_router)
app.include_router(history_router)
app.include_router(tts_router)
app.include_router(name_en_router)

_media = media_root()
_media.mkdir(parents=True, exist_ok=True)
app.mount("/media", StaticFiles(directory=str(_media)), name="media")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "shitu-api"}
