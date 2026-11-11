"""Состояние демо-пользователя в памяти процесса.

Сегодняшняя версия сервера — без авторизации: один пользователь «demo», кладовка, снимки подбора
и результаты распознавания живут в памяти и сбрасываются при перезапуске. Пути и форматы — как
в контракте (/me/pantry, /recommendations, /recognitions), поэтому Android не придётся
переписывать, когда появятся вход и хранение в БД.
"""

from __future__ import annotations

import threading
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Any

from dishgraph import Catalog

DEMO_USER_ID = "demo"
SNAPSHOT_TTL = timedelta(hours=1)
RECOGNITION_TTL = timedelta(hours=1)

# Подобран на реальном каталоге: при нём сразу доступно больше всего блюд (см. engine/README).
DEMO_PANTRY = [
    "Масло растительное", "Мука", "Дрожжи сухие", "Сахарная пудра", "Яйцо куриное", "Масло сливочное",
    "Молоко", "Лук репчатый", "Картофель", "Масло оливковое", "Сгущённое молоко", "Сметана", "Укроп",
    "Сливки", "Сухой творог", "Копчёная грудинка", "Сливки 33%", "Лайм", "Чеснок",
]


def now() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime) -> str:
    return dt.isoformat().replace("+00:00", "Z")


def new_id(prefix: str) -> str:
    return f"{prefix}-{uuid.uuid4().hex[:16]}"


@dataclass
class Snapshot:
    id: str
    request_id: str
    servings: int
    filters: dict[str, Any]
    visibility: str
    options: list[Any]  # DishOption в порядке выдачи
    graph: dict[str, Any]  # граф движка (build_graph)
    unknown_ids: frozenset[str]  # продукты кладовки без количества
    state_version: int
    expires_at: datetime


@dataclass
class RecognitionJob:
    id: str
    kind: str
    status: str
    lines: list[Any]
    failure: dict[str, Any] | None
    expires_at: datetime
    imported: bool = False


@dataclass
class DemoState:
    # код ингредиента -> {"value": ..., "unit": ...} или None («есть, количество не указано»)
    pantry: dict[str, dict[str, Any] | None] = field(default_factory=dict)
    state_version: int = 0
    snapshots: dict[str, Snapshot] = field(default_factory=dict)
    recognitions: dict[str, RecognitionJob] = field(default_factory=dict)
    lock: threading.RLock = field(default_factory=threading.RLock)

    def bump(self) -> int:
        self.state_version += 1
        return self.state_version

    def cleanup(self) -> None:
        t = now()
        self.snapshots = {k: v for k, v in self.snapshots.items() if v.expires_at > t}
        self.recognitions = {k: v for k, v in self.recognitions.items() if v.expires_at > t}

    @classmethod
    def with_demo_pantry(cls, catalog: Catalog) -> DemoState:
        by_name = {ing.name: code for code, ing in catalog.ingredients.items()}
        return cls(pantry={by_name[n]: None for n in DEMO_PANTRY if n in by_name})
