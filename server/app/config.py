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


@lru_cache
def get_settings() -> Settings:
    return Settings()
