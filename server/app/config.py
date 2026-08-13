from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

_SERVER_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=str(_SERVER_DIR / ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    baidu_api_key: str = ""
    baidu_secret_key: str = ""
    app_host: str = "0.0.0.0"
    app_port: int = 8000
    # 默认空 = SQLite 文件 server/data/shitu.db；上云可改：
    # DATABASE_URL=postgresql+psycopg://user:pass@host:5432/shitu
    database_url: str = ""


@lru_cache
def get_settings() -> Settings:
    return Settings()
