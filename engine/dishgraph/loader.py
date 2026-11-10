"""Загрузка и проверка каталога. Пока базы нет — читаем data/fixtures.json"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from .models import Catalog, Ingredient, Recipe, RecipeItem

DEFAULT_FIXTURES = Path(__file__).resolve().parent.parent / "data" / "fixtures.json"
CODE_RE = re.compile(r"^[a-z][a-z0-9_]*$")


class CatalogError(ValueError):
    pass

def load_catalog(path: str | Path = DEFAULT_FIXTURES) -> Catalog:
    """Читает JSON-файлик"""
    with open(path, encoding="utf-8") as f:
        return catalog_from_dict(json.load(f))


def _ingredient(raw: dict[str, Any]) -> Ingredient:
    """Превращает словарь в модель"""
    ing = Ingredient(
        code=raw["code"],
        name=raw["name"],
        package_g=float(raw["package_g"]),
        package_price=float(raw["package_price"]),
        kcal=float(raw["kcal"]),
        protein=float(raw["protein"]),
        fat=float(raw["fat"]),
        carbs=float(raw["carbs"]),
        is_staple=bool(raw.get("is_staple", False)),
        allergens=frozenset(raw.get("allergens", [])),
        aliases=tuple(raw.get("aliases", [])),
        display_unit=raw.get("display_unit", "g"),
        grams_per_piece=(float(raw["grams_per_piece"]) if raw.get("grams_per_piece") is not None else None),
    )
    c = ing.code
    if not CODE_RE.match(c):
        raise CatalogError(f"Код ингредиента {c!r}: только a-z, 0-9 и _, начинается с буквы")
    if not ing.name.strip() or ing.name != ing.name.strip():
        raise CatalogError(f"У {c!r} пустое название или пробелы по краям")
    if ing.package_g <= 0:
        raise CatalogError(f"У {c!r} package_g должен быть > 0")
    if ing.package_price < 0:
        raise CatalogError(f"У {c!r} отрицательная цена")
    if not 0 <= ing.kcal <= 900:
        raise CatalogError(f"У {c!r} kcal вне диапазона 0–900")
    if min(ing.protein, ing.fat, ing.carbs) < 0 or ing.protein + ing.fat + ing.carbs > 100:
        raise CatalogError(f"У {c!r} БЖУ отрицательные или в сумме больше 100 г на 100 г")
    if ing.display_unit not in ("g", "ml", "pcs"):
        raise CatalogError(f"У {c!r} display_unit должен быть g, ml или pcs")
    if ing.display_unit == "pcs" and not ing.grams_per_piece:
        raise CatalogError(f"У штучного {c!r} нужен grams_per_piece")
    return ing


def _recipe(raw: dict[str, Any], ingredients: dict[str, Ingredient]) -> Recipe:
    """Превращает словари в модели"""
    items = tuple(
        RecipeItem(
            code=it["code"],
            qty_g=None if it.get("qty_g") is None else float(it["qty_g"]),  # NULL в БД — не указано
            is_optional=bool(it.get("is_optional", False)),
        )
        for it in raw["items"]
    )
    recipe = Recipe(
        id=str(raw["id"]),
        title=raw["title"],
        cook_time_min=int(raw["cook_time_min"]),
        servings=int(raw["servings"]),
        items=items,
        needs_microwave=bool(raw.get("needs_microwave", False)),
        needs_stove=bool(raw.get("needs_stove", False)),
        needs_oven=bool(raw.get("needs_oven", False)),
        steps=tuple(raw.get("steps", [])),
        description=raw.get("description"),
    )
    rid = recipe.id
    if recipe.servings <= 0:
        raise CatalogError(f"У рецепта {rid!r} servings должен быть > 0")
    if recipe.cook_time_min <= 0:
        raise CatalogError(f"У рецепта {rid!r} cook_time_min должен быть > 0")
    seen: set[str] = set()
    for it in items:
        if it.code not in ingredients:
            raise CatalogError(f"Рецепт {rid!r} ссылается на неизвестный ингредиент {it.code!r}")
        if it.code in seen:
            raise CatalogError(f"В рецепте {rid!r} ингредиент {it.code!r} указан дважды")
        if it.qty_g is not None and it.qty_g <= 0:
            raise CatalogError(f"В рецепте {rid!r} qty_g должен быть > 0 или не указан")
        seen.add(it.code)
    if not recipe.required_items:
        raise CatalogError(f"У рецепта {rid!r} нет обязательных ингредиентов")
    return recipe


def catalog_from_dict(data: dict[str, Any]) -> Catalog:
    """Собирает каталог из словаря"""
    ingredients: dict[str, Ingredient] = {}
    names: set[str] = set()
    for raw in data["ingredients"]:
        ing = _ingredient(raw)
        if ing.code in ingredients:
            raise CatalogError(f"Ингредиент {ing.code!r} встречается дважды")
        if ing.name.lower() in names:
            raise CatalogError(f"Название {ing.name!r} встречается дважды")
        ingredients[ing.code] = ing
        names.add(ing.name.lower())

    recipes: list[Recipe] = []
    seen: set[str] = set()
    for raw in data["recipes"]:
        recipe = _recipe(raw, ingredients)
        if recipe.id in seen:
            raise CatalogError(f"Рецепт {recipe.id!r} встречается дважды")
        seen.add(recipe.id)
        recipes.append(recipe)

    return Catalog(ingredients=ingredients, recipes=tuple(recipes))
