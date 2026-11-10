"""Перевод результатов движка в форматы контракта (docs/api/openapi.yaml)."""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from typing import Any

from dishgraph import Catalog, DishOption, Recipe

ALLERGEN_NAMES = {
    "gluten": "Глютен", "milk": "Молоко", "eggs": "Яйца", "fish": "Рыба", "crustaceans": "Ракообразные",
    "molluscs": "Моллюски", "peanuts": "Арахис", "nuts": "Орехи", "soy": "Соя", "sesame": "Кунжут",
    "mustard": "Горчица", "celery": "Сельдерей", "lupin": "Люпин", "sulphites": "Сульфиты",
}


# --- базовые типы ----------------------------------------------------------------------------

def money(rub: float | None) -> dict[str, Any] | None:
    """Рубли → Money (целые копейки)."""
    if rub is None:
        return None
    return {"minor_units": int(round(rub * 100)), "currency": "RUB"}


def rub(m: Mapping[str, Any]) -> float:
    return m["minor_units"] / 100


def grams(catalog: Catalog, code: str, quantity: Mapping[str, Any] | None) -> float | None:
    """Quantity из API → граммы для движка. None — количество неизвестно (считается достаточным)."""
    if quantity is None:
        return None
    value, unit = float(quantity["value"]), quantity["unit"]
    if unit == "pcs":
        per_piece = catalog.ingredients[code].grams_per_piece
        return value * per_piece if per_piece else None
    return value  # g; ml считаем 1:1 (плотности в БД нет)


def engine_pantry(catalog: Catalog, pantry: Mapping[str, Mapping[str, Any] | None]) -> dict[str, float | None]:
    return {code: grams(catalog, code, q) for code, q in pantry.items() if code in catalog.ingredients}


def quantity_g(value: float | None) -> dict[str, Any] | None:
    return None if value is None else {"value": round(value, 2), "unit": "g"}


def allowed_units(catalog: Catalog, code: str) -> list[str]:
    ing = catalog.ingredients[code]
    units = ["g"]
    if ing.display_unit == "ml":
        units.append("ml")
    if ing.grams_per_piece:
        units.append("pcs")
    return units


def package_id(code: str) -> str:
    return f"{code}-pack"


def offer(catalog: Catalog, code: str) -> dict[str, Any]:
    ing = catalog.ingredients[code]
    return {
        "package_id": package_id(code),
        "quantity": {"value": ing.package_g, "unit": "g"},
        "price": money(ing.package_price),
        "source": None,
    }


def shopping_item(catalog: Catalog, code: str, packs: int) -> dict[str, Any]:
    ing = catalog.ingredients[code]
    return {
        "key": f"{code}:{package_id(code)}",
        "ingredient_id": code,
        "package_id": package_id(code),
        "name": ing.name,
        "package_quantity": {"value": ing.package_g, "unit": "g"},
        "package_count": packs,
        "total_price": money(packs * ing.package_price),
    }


def allergen_assessment(codes: Iterable[str]) -> dict[str, Any]:
    return {"contains": sorted(set(codes)), "completeness": "complete", "sources": []}


def ingredient(catalog: Catalog, code: str, favorite: bool = False) -> dict[str, Any]:
    ing = catalog.ingredients[code]
    return {
        "id": code,
        "name": ing.name,
        "allowed_units": allowed_units(catalog, code),
        "is_favorite": favorite,
        "allergens": allergen_assessment(ing.allergens),
        "offers": [offer(catalog, code)],
    }


def pantry_items(catalog: Catalog, pantry: Mapping[str, Mapping[str, Any] | None]) -> list[dict[str, Any]]:
    return sorted(
        ({"ingredient_id": code, "name": catalog.name(code), "quantity": q} for code, q in pantry.items()),
        key=lambda i: i["name"],
    )


# --- рецепты -----------------------------------------------------------------------------------

def suitability(recipe_allergens: Mapping[str, Iterable[str]], excluded: Iterable[str]) -> dict[str, Any]:
    hits = sorted(set(excluded) & set(recipe_allergens))
    if not hits:
        return {"status": "allowed", "reasons": []}
    return {
        "status": "hidden",
        "reasons": [
            {
                "code": "allergen",
                "message": f"Содержит: {ALLERGEN_NAMES.get(a, a).lower()}",
                "ingredient_ids": sorted(recipe_allergens[a]),
                "restriction_ids": [a],
            }
            for a in hits
        ],
    }


def unknown_quantity_ids(recipe: Recipe, unknown: Iterable[str]) -> list[str]:
    """Продукты кладовки без количества, которые идут в этот рецепт (подсказка «проверьте количество»)."""
    used = {i.code for i in recipe.required_items}
    return sorted(used & set(unknown))


def recipe_card(
    catalog: Catalog,
    option: DishOption,
    unknown: Iterable[str] = (),
    excluded_allergens: Iterable[str] = (),
) -> dict[str, Any]:
    r, m = option.recipe, option.metrics
    return {
        "id": r.id,
        "title": r.title,
        "photo_url": r.image_url,
        "servings": option.portions,
        "minutes": r.cook_time_min or None,
        "nutrition_per_serving": {"kcal": m.kcal, "protein_g": m.protein, "fat_g": m.fat, "carbs_g": m.carbs},
        "nutrition_source": None,
        "buy_cost": money(m.buy_cost),
        "availability": {
            "status": "ready" if option.level == 0 else "missing",
            "missing_count": option.level,
            "unknown_quantity_ids": unknown_quantity_ids(r, unknown),
        },
        "suitability": suitability(m.allergens, excluded_allergens),
        "allergens": allergen_assessment(m.allergens),
        "is_favorite": False,
        "methods": list(r.methods),
    }


def recipe_items(
    catalog: Catalog,
    option: DishOption,
    pantry_g: Mapping[str, float | None],
) -> list[dict[str, Any]]:
    """Состав рецепта с отметками «есть / не хватает / по вкусу» на число порций option."""
    r = option.recipe
    factor = option.portions / r.servings
    rows = []
    for item in r.items:
        code = item.code
        need = None if item.qty_g is None else item.qty_g * factor
        have = pantry_g.get(code)
        in_pantry = code in pantry_g
        if item.is_optional:
            availability, shortage = "optional", None
        elif code in option.missing_g:
            availability, shortage = "missing", option.missing_g[code]
        else:
            availability, shortage = "enough", None
        rows.append(
            {
                "ingredient_id": code,
                "name": catalog.name(code),
                "required": quantity_g(need),
                "available": quantity_g(have) if in_pantry else None,
                "shortage": quantity_g(shortage) if (shortage is not None and item.qty_g is not None) else None,
                "availability": availability,
                "optional": item.is_optional,
                "original_amount": None,
                "offer": offer(catalog, code),
            }
        )
    return rows


def missing_shopping_items(catalog: Catalog, option: DishOption) -> list[dict[str, Any]]:
    return [
        shopping_item(catalog, code, catalog.packs_needed(code, g)) for code, g in sorted(option.missing_g.items())
    ]


# --- граф ----------------------------------------------------------------------------------

def graph(
    catalog: Catalog,
    engine_graph: Mapping[str, Any],
    options: Iterable[DishOption],
    unknown: Iterable[str] = (),
    excluded_allergens: Iterable[str] = (),
) -> dict[str, Any]:
    """Граф движка (home / buy:… / dish:…) → Graph из контракта."""
    by_recipe = {o.recipe.id: o for o in options}
    nodes = []
    for n in engine_graph["nodes"]:
        if n["type"] == "home":
            nodes.append({"id": n["id"], "kind": "home", "label": "Дома", "level": 0})
        elif n["type"] == "purchase":
            items = [shopping_item(catalog, i["code"], i["packs"]) for i in n["items"]]
            nodes.append(
                {
                    "id": n["id"],
                    "kind": "purchase",
                    "label": "Купить: " + ", ".join(i["name"] for i in items),
                    "level": n["level"],
                    "shopping_items": items,
                    "cost": money(n["cost"]),
                    "dish_count": n["dish_count"],
                }
            )
        else:
            option = by_recipe[n["recipe_id"]]
            nodes.append(
                {
                    "id": n["id"],
                    "kind": "recipe",
                    "label": n["title"],
                    "level": n["level"],
                    "recipe_id": n["recipe_id"],
                    "recipe": recipe_card(catalog, option, unknown, excluded_allergens),
                }
            )
    edges = []
    for e in engine_graph["edges"]:
        if e["to"].startswith("buy:"):
            edges.append(
                {
                    "source": e["from"],
                    "target": e["to"],
                    "kind": "extends",
                    "add": [shopping_item(catalog, i["code"], i["packs"]) for i in e["add"]],
                    "add_cost": money(e["add_cost"]),
                }
            )
        else:
            edges.append({"source": e["from"], "target": e["to"], "kind": "unlocks"})
    return {"scope": "snapshot", "nodes": nodes, "edges": edges, "unrepresented_recipe_ids": []}


# --- каталог для текущего Android-клиента (демо, не из контракта) ---------------------------------

ANDROID_ALLERGENS = {"milk": "MILK", "eggs": "EGGS", "gluten": "GLUTEN", "nuts": "NUTS", "peanuts": "NUTS",
                     "fish": "FISH", "soy": "SOY"}
ANDROID_METHODS = {"stove": "STOVE", "oven": "OVEN", "microwave": "MICROWAVE", "no_cook": "NO_COOK"}
ANDROID_MAX_SERVINGS = 12  # Recipe в приложении требует servings в 1..12


def android_catalog(catalog: Catalog, demo_pantry: Iterable[str], version: str) -> dict[str, Any]:
    """Каталог в формате доменных моделей Android (Ingredient, Recipe, PackageOffer).

    Нужен, пока приложение считает подбор само (локальный RecipeEngine). Особенности:
      * всё в граммах, цены в копейках;
      * базовые продукты и «по вкусу» в состав не попадают — в приложении нет «есть всегда»;
      * рецепты больше чем на 12 порций пересчитываются на 12 (граммы пропорционально);
      * аллергены — только те, что есть в enum приложения; если какой-то не помещается,
        allergen_data_complete = false.
    """
    from dishgraph import dish_metrics

    staples = catalog.staples
    ingredients = [
        {
            "id": code,
            "name": ing.name,
            "unit": "GRAM",
            "grams_per_piece": ing.grams_per_piece,
            "offer": {"quantity": {"value": ing.package_g, "unit": "GRAM"},
                      "price_kopecks": int(round(ing.package_price * 100))},
        }
        for code, ing in sorted(catalog.ingredients.items(), key=lambda kv: kv[1].name)
    ]
    recipes = []
    for r in catalog.recipes:
        servings = min(r.servings, ANDROID_MAX_SERVINGS)
        factor = servings / r.servings
        items = [i for i in r.required_items if i.code not in staples and i.qty_g]
        m = dish_metrics(r, {}, catalog)
        mapped = {ANDROID_ALLERGENS[a] for a in m.allergens if a in ANDROID_ALLERGENS}
        recipes.append(
            {
                "id": r.id,
                "title": r.title,
                "ingredients": [{"ingredient_id": i.code, "quantity": {"value": round(i.qty_g * factor, 2), "unit": "GRAM"}}
                                for i in items],
                "steps": list(r.steps),
                "minutes": max(1, r.cook_time_min),
                "servings": servings,
                "nutrition": {"kcal": round(m.kcal), "protein": round(m.protein), "fat": round(m.fat),
                              "carbs": round(m.carbs)},
                "allergens": sorted(mapped),
                "allergen_data_complete": all(a in ANDROID_ALLERGENS for a in m.allergens),
                "dietary": {"vegetarian": None, "vegan": None,
                            "gluten_free": "gluten" not in m.allergens, "lactose_free": "milk" not in m.allergens},
                "methods": [ANDROID_METHODS[x] for x in r.methods],
                "photo": r.image_url or "",
            }
        )
    return {
        "catalog_version": version,
        "demo_pantry": [c for c in demo_pantry if c in catalog.ingredients],
        "ingredients": ingredients,
        "recipes": [r for r in recipes if r["ingredients"]],
    }
