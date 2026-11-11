"""Настройки сервера — из переменных окружения (и файла backend/.env, если он есть)."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def _load_dotenv(path: Path) -> None:
    """KEY=VALUE из .env в окружение, не перезаписывая уже заданные переменные."""
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip("'\""))


@dataclass(frozen=True)
class Settings:
    # Откуда брать каталог: PostgreSQL (если задан DATABASE_URL) или напрямую из дампа seed.sql
    database_url: str | None
    seed_path: Path
    catalog_sql_path: Path
    # Положить в кладовку демо-пользователя подобранный набор продуктов при старте
    demo_pantry: bool

    @classmethod
    def from_env(cls) -> Settings:
        _load_dotenv(REPO_ROOT / "backend" / ".env")
        return cls(
            database_url=os.environ.get("DATABASE_URL") or None,
            seed_path=Path(os.environ.get("SEED_PATH", REPO_ROOT / "db" / "seed.sql")),
            catalog_sql_path=Path(os.environ.get("CATALOG_SQL_PATH", REPO_ROOT / "engine" / "sql" / "catalog.sql")),
            demo_pantry=os.environ.get("DEMO_PANTRY", "true").lower() in ("1", "true", "yes"),
        )
