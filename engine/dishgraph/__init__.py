"""Движок графа достижимых блюд.

Типичное использование (так его вызывает API):

    catalog = load_catalog()  # или catalog_from_dict(...) из данных БД
    options = reachable_dishes(
        {"egg": 110, "milk": None},          # кладовка: граммы или None («есть»)
        catalog,
        equipment={"stove", "microwave"},    # техника пользователя
        hidden={"12", "40"},                 # скрытые блюда из user_recipe_visibility
    )
    graph = build_graph(options, catalog)
    singles = best_single_purchases(options, catalog)
    plan = best_purchases(options, catalog, budget=500)

    index = SearchIndex(catalog)            # один раз при старте
    index.search("малако")                  # автодополнение → [SearchHit(code="milk", ...)]
"""

from .core import (
    DishMetrics,
    DishOption,
    Pantry,
    dish_metrics,
    dish_option,
    missing,
    missing_grams,
    normalize_pantry,
    reachable_dishes,
)
from .graph import build_graph
from .loader import CatalogError, catalog_from_dict, load_catalog
from .models import COOKING_METHODS, EQUIPMENT, Catalog, Ingredient, Recipe, RecipeItem
from .purchases import BudgetPlan, PlanStep, SinglePurchase, best_purchases, best_single_purchases
from .search import SearchHit, SearchIndex, search_ingredients

__all__ = [
    "COOKING_METHODS",
    "EQUIPMENT",
    "BudgetPlan",
    "Catalog",
    "CatalogError",
    "DishMetrics",
    "DishOption",
    "Ingredient",
    "Pantry",
    "PlanStep",
    "Recipe",
    "RecipeItem",
    "SearchHit",
    "SearchIndex",
    "SinglePurchase",
    "best_purchases",
    "best_single_purchases",
    "build_graph",
    "catalog_from_dict",
    "dish_metrics",
    "dish_option",
    "load_catalog",
    "missing",
    "missing_grams",
    "normalize_pantry",
    "reachable_dishes",
    "search_ingredients",
]
