"""Загрузка каталога для движка.

1. DATABASE_URL задан — запрос engine/sql/catalog.sql к PostgreSQL (боевой режим, docker compose).
2. Иначе — данные из дампа db/seed.sql (блоки COPY), без базы и Docker. Удобно для демо на ноутбуке:
   результат тот же, что у catalog.sql, потому что дамп — это и есть база Карины.
"""

from __future__ import annotations

import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any

from dishgraph import Catalog, catalog_from_dict

from .config import Settings

_COPY_RE = re.compile(r"COPY public\.(\w+) \(([^)]*)\) FROM stdin;")
_ESCAPES = {"\\n": "\n", "\\t": "\t", "\\r": "\r", "\\\\": "\\"}


def _unescape(value: str) -> str | None:
    if value == "\\N":
        return None
    return re.sub(r"\\[ntr\\]", lambda m: _ESCAPES[m.group(0)], value)


def read_copy_tables(path: Path) -> dict[str, list[dict[str, str | None]]]:
    """Строки всех COPY-блоков pg_dump: {таблица: [{колонка: значение}]}."""
    tables: dict[str, list[dict[str, str | None]]] = {}
    current: str | None = None
    columns: list[str] = []
    for line in path.read_text(encoding="utf-8").split("\n"):
        if current is None:
            m = _COPY_RE.match(line)
            if m:
                current, columns = m.group(1), [c.strip() for c in m.group(2).split(",")]
                tables[current] = []
            continue
        if line == "\\.":
            current = None
            continue
        tables[current].append(dict(zip(columns, (_unescape(v) for v in line.split("\t")))))
    return tables


def catalog_dict_from_seed(path: Path) -> dict[str, Any]:
    """То же, что возвращает engine/sql/catalog.sql, но из дампа."""
    t = read_copy_tables(path)
    num = lambda v: None if v is None else float(v)  # noqa: E731
    flag = lambda v: v == "t"  # noqa: E731

    allergen_code = {r["id"]: r["code"] for r in t["allergens"]}
    by_id = {r["id"]: r for r in t["ingredients"]}
    allergens: dict[str, list[str]] = defaultdict(list)
    for r in t["ingredient_allergens"]:
        allergens[r["ingredient_id"]].append(allergen_code[r["allergen_id"]])
    aliases: dict[str, list[str]] = defaultdict(list)
    for r in t["ingredient_aliases"]:
        aliases[r["ingredient_id"]].append(r["alias"])
    steps: dict[str, list[tuple[int, str]]] = defaultdict(list)
    for r in t["recipe_steps"]:
        steps[r["recipe_id"]].append((int(r["step_no"]), r["instruction"]))
    items: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for r in t["recipe_ingredients"]:
        items[r["recipe_id"]].append(
            {"code": by_id[r["ingredient_id"]]["code"], "qty_g": num(r["qty_g"]), "is_optional": flag(r["is_optional"])}
        )

    return {
        "ingredients": [
            {
                "code": r["code"], "name": r["name"], "is_staple": flag(r["is_staple"]),
                "package_g": num(r["package_g"]), "package_price": num(r["package_price"]),
                "kcal": num(r["kcal"]), "protein": num(r["protein"]), "fat": num(r["fat"]), "carbs": num(r["carbs"]),
                "display_unit": r["display_unit"], "grams_per_piece": num(r["grams_per_piece"]),
                "allergens": sorted(allergens[r["id"]]), "aliases": sorted(aliases[r["id"]]),
            }
            for r in t["ingredients"]
        ],
        "recipes": [
            {
                "id": r["id"], "title": r["title"], "description": r["description"],
                "servings": int(r["servings"]), "cook_time_min": int(r["cook_time_min"]),
                "needs_microwave": flag(r["needs_microwave"]), "needs_stove": flag(r["needs_stove"]),
                "needs_oven": flag(r["needs_oven"]), "no_cook": flag(r.get("no_cook")),
                "image_url": r.get("image_url"),
                "steps": [s for _, s in sorted(steps[r["id"]])], "items": items[r["id"]],
            }
            for r in t["recipes"]
            if r.get("author_id") is None  # личные рецепты в общий каталог не попадают
        ],
    }


def catalog_dict_from_db(database_url: str, catalog_sql: Path) -> dict[str, Any]:
    import psycopg

    with psycopg.connect(database_url) as conn:
        row = conn.execute(catalog_sql.read_text(encoding="utf-8")).fetchone()
    data = row[0]
    return json.loads(data) if isinstance(data, str) else data


def load(settings: Settings) -> tuple[Catalog, str, str]:
    """(каталог, версия каталога, откуда загружен)."""
    if settings.database_url:
        data, source = catalog_dict_from_db(settings.database_url, settings.catalog_sql_path), "postgres"
    else:
        data, source = catalog_dict_from_seed(settings.seed_path), f"seed:{settings.seed_path.name}"
    version = hashlib.sha256(json.dumps(data, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:12]
    return catalog_from_dict(data), f"catalog-{version}", source
