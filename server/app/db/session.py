from __future__ import annotations

from collections.abc import Generator
from pathlib import Path

from sqlalchemy import create_engine, event, inspect, text
from sqlalchemy.orm import Session, sessionmaker

from app.config import get_settings
from app.db.models import Base

_SERVER_DIR = Path(__file__).resolve().parent.parent.parent
_DATA_DIR = _SERVER_DIR / "data"
_DEFAULT_SQLITE = f"sqlite:///{(_DATA_DIR / 'shitu.db').as_posix()}"


def _database_url() -> str:
    url = (get_settings().database_url or "").strip()
    return url or _DEFAULT_SQLITE


def _make_engine():
    url = _database_url()
    connect_args = {}
    if url.startswith("sqlite"):
        _DATA_DIR.mkdir(parents=True, exist_ok=True)
        connect_args["check_same_thread"] = False
    engine = create_engine(url, future=True, connect_args=connect_args)
    if url.startswith("sqlite"):

        @event.listens_for(engine, "connect")
        def _sqlite_fk(dbapi_conn, _):  # type: ignore[no-untyped-def]
            dbapi_conn.execute("PRAGMA foreign_keys=ON")

    return engine


engine = _make_engine()
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, future=True)


def _ensure_sqlite_columns() -> None:
    """create_all 不会给已有表加列；SQLite 下补齐缺失列。"""
    url = _database_url()
    if not url.startswith("sqlite"):
        return
    insp = inspect(engine)
    if "learning_records" not in insp.get_table_names():
        return
    cols = {c["name"] for c in insp.get_columns("learning_records")}
    if "description" not in cols:
        with engine.begin() as conn:
            conn.execute(
                text(
                    "ALTER TABLE learning_records "
                    "ADD COLUMN description TEXT DEFAULT ''"
                )
            )


def init_db() -> None:
    _DATA_DIR.mkdir(parents=True, exist_ok=True)
    (_DATA_DIR / "thumbs").mkdir(parents=True, exist_ok=True)
    Base.metadata.create_all(bind=engine)
    _ensure_sqlite_columns()


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def media_root() -> Path:
    return _DATA_DIR
