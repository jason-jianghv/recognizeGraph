import logging
import time

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.routers.recognize import router as recognize_router

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("shitu")

app = FastAPI(
    title="识图 API",
    description="儿童拍照识物后端（百度智能云图像识别）",
    version="0.1.0",
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


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "shitu-api"}
