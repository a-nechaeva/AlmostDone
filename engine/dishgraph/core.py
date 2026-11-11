"""Ядро: подбор блюд, уровни 0–3, метрики блюда, фильтры"""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from typing import Any, Union

from .models import COOKING_METHODS, Catalog, Recipe

# Кладовка: {код: граммы} или {код: None} («есть, количество не указано» — хватает на любое блюдо)
# Можно передать просто набор кодов: {"egg", "milk"} — то же, что все None.
Pantry = Union[Mapping[str, Union[float, None]], Iterable[str]]


def normalize_pantry(pantry: Pantry) -> dict[str, float | None]:
    """Приводит оба варианта Pantry к словарю"""
    if isinstance(pantry, Mapping):
        return {code: (None if qty is None else float(qty)) for code, qty in pantry.items()}
    return {code: None for code in pantry}


@dataclass(frozen=True)
class DishMetrics:
    buy_cost: float  # сколько стоит докупить недостающее целыми упаковками, ₽
    portion_cost: float  # себестоимость одной порции, ₽
    cook_time_min: int
    kcal: float  # на порцию
    protein: float
    fat: float
    carbs: float
    # аллерген -> из каких ингредиентов он пришёл: {"milk": ("butter", "milk")}
    allergens: dict[str, tuple[str, ...]]
    # False — у какого-то обязательного ингредиента не указаны граммы: КБЖУ и цена порции занижены
    nutrition_complete: bool = True


@dataclass(frozen=True)
class DishOption:
    recipe: Recipe
    missing_g: dict[str, float]  # код -> сколько граммов не хватает
    metrics: DishMetrics
    servings: int | None = None  # на сколько порций посчитано недостающее; None — порции рецепта

    @property
    def portions(self) -> int:
        return self.servings or self.recipe.servings

    @property
    def missing(self) -> frozenset[str]:
        return frozenset(self.missing_g)

    @property
    def level(self) -> int:
        """0 — всё есть дома, 1–3 — сколько ингредиентов докупить."""
        return len(self.missing_g)

    def to_dict(self, catalog: Catalog) -> dict[str, Any]:
        m = self.metrics
        return {
            "id": self.recipe.id,
            "title": self.recipe.title,
            "level": self.level,
            "servings": self.portions,
            "missing": [
                {
                    "code": c,
                    "name": catalog.name(c),
                    "missing_g": round(g, 1),
                    "packs": catalog.packs_needed(c, g),
                    "cost": catalog.pack_cost(c, g),
                }
                for c, g in sorted(self.missing_g.items())
            ],
            "buy_cost": m.buy_cost,
            "portion_cost": m.portion_cost,
            "cook_time_min": m.cook_time_min,
            "equipment": sorted(self.recipe.equipment),
            "kcal": m.kcal,
            "protein": m.protein,
            "fat": m.fat,
            "carbs": m.carbs,
            "nutrition_complete": m.nutrition_complete,
            "allergens": sorted(m.allergens),
            "allergen_sources": {a: list(src) for a, src in sorted(m.allergens.items())},
        }


def missing_grams(
    recipe: Recipe,
    pantry: Pantry,
    staples: Iterable[str] = (),
    catalog: Catalog | None = None,
    servings: int | None = None,
) -> dict[str, float]:
    """Сколько граммов каждого обязательного ингредиента не хватает.
    Базовые продукты (is_staple) и ингредиенты «по вкусу» не считаются.

    Если в рецепте граммы не указаны: продукт есть дома — хватает; продукта нет — нужна одна
    упаковка (вес упаковки из каталога; без каталога — 1 г, тоже одна упаковка).
    servings — на сколько порций готовим: граммы рецепта пересчитываются пропорционально.
    """
    factor = (servings / recipe.servings) if servings else 1.0
    have = normalize_pantry(pantry)
    staple_set = frozenset(staples)
    result: dict[str, float] = {}
    for item in recipe.required_items:
        if item.code in staple_set:
            continue
        if item.qty_g is None:
            if item.code not in have:
                result[item.code] = catalog.ingredients[item.code].package_g if catalog else 1.0
            continue
        need = item.qty_g * factor
        if item.code not in have:
            result[item.code] = need
            continue
        qty = have[item.code]
        if qty is not None and qty < need - 1e-9:
            result[item.code] = need - qty
    return result


def missing(recipe: Recipe, pantry: Pantry, staples: Iterable[str] = ()) -> frozenset[str]:
    """Коды недостающих ингредиентов."""
    return frozenset(missing_grams(recipe, pantry, staples))


def dish_metrics(recipe: Recipe, missing_g: Mapping[str, float], catalog: Catalog) -> DishMetrics:
    """Метрики по обязательным ингредиентам (включая базовые) — так же, как recipe_nutrition в БД."""
    ings = catalog.ingredients
    buy_cost = sum(catalog.pack_cost(c, g) for c, g in missing_g.items())

    total_cost = kcal = protein = fat = carbs = 0.0
    complete = True
    allergens: dict[str, set[str]] = {}
    for item in recipe.required_items:
        ing = ings[item.code]
        for a in ing.allergens:  # аллергены — даже если граммы не указаны
            allergens.setdefault(a, set()).add(ing.code)
        if item.qty_g is None:
            complete = False  # вклад в КБЖУ и цену порции неизвестен
            continue
        total_cost += item.qty_g / ing.package_g * ing.package_price
        k = item.qty_g / 100
        kcal += k * ing.kcal
        protein += k * ing.protein
        fat += k * ing.fat
        carbs += k * ing.carbs

    s = recipe.servings
    return DishMetrics(
        buy_cost=round(buy_cost, 2),
        portion_cost=round(total_cost / s, 1),
        cook_time_min=recipe.cook_time_min,
        kcal=round(kcal / s, 1),
        protein=round(protein / s, 1),
        fat=round(fat / s, 1),
        carbs=round(carbs / s, 1),
        allergens={a: tuple(sorted(src)) for a, src in allergens.items()},
        nutrition_complete=complete,
    )


def dish_option(recipe: Recipe, pantry: Pantry, catalog: Catalog, servings: int | None = None) -> DishOption:
    """Одно блюдо без фильтров — например, для карточки или раздела «Скрытые блюда»."""
    miss = missing_grams(recipe, pantry, catalog.staples, catalog, servings)
    return DishOption(recipe=recipe, missing_g=miss, metrics=dish_metrics(recipe, miss, catalog), servings=servings)


def reachable_dishes(
    pantry: Pantry,
    catalog: Catalog,
    *,
    max_missing: int = 3,
    exclude_allergens: Iterable[str] = (),
    max_minutes: int | None = None,
    max_kcal: float | None = None,
    equipment: Iterable[str] | None = None,
    hidden: Iterable[str] = (),
    servings: int | None = None,
) -> list[DishOption]:
    """Блюда, которые можно приготовить сейчас (уровень 0) или докупив до max_missing ингредиентов.

    equipment — какая техника есть у пользователя ({"microwave"} = только микроволновка; значения
                stove / oven / microwave / no_cook, как в API); None — не фильтровать.
                Рецепт «без готовки» проходит всегда, без сведений о технике — только при всей технике.
    servings  — на сколько порций готовим (недостающее и цена докупки пересчитываются); None — как в рецепте.
    hidden    — id рецептов, скрытых для пользователя (из user_recipe_visibility, is_hidden = true).

    Сортировка: уровень, затем цена докупки, затем время."""
    have = normalize_pantry(pantry)
    banned = frozenset(exclude_allergens)
    hidden_ids = frozenset(hidden)
    available = None if equipment is None else frozenset(equipment)
    if available is not None and not available <= set(COOKING_METHODS):
        raise ValueError(f"Неизвестная техника: {sorted(available - set(COOKING_METHODS))}")

    result: list[DishOption] = []
    for recipe in catalog.recipes:
        if recipe.id in hidden_ids:
            continue
        if max_minutes is not None and recipe.cook_time_min > max_minutes:
            continue
        if available is not None and not recipe.fits_equipment(available):
            continue
        miss = missing_grams(recipe, have, catalog.staples, catalog, servings)
        if len(miss) > max_missing:
            continue
        metrics = dish_metrics(recipe, miss, catalog)
        if banned & metrics.allergens.keys():
            continue
        if max_kcal is not None and metrics.kcal > max_kcal:
            continue
        result.append(DishOption(recipe=recipe, missing_g=miss, metrics=metrics, servings=servings))

    result.sort(key=lambda o: (o.level, o.metrics.buy_cost, o.metrics.cook_time_min, o.recipe.title))
    return result
