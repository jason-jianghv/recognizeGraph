#!/usr/bin/env python3
"""手动补种子：python scripts/seed_catalog.py"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))

from app.db.session import init_db  # noqa: E402
from app.services.catalog_seed import seed_catalog_from_name_en  # noqa: E402


def main() -> None:
    init_db()
    stats = seed_catalog_from_name_en()
    print(stats)


if __name__ == "__main__":
    main()
