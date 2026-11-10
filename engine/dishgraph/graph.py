"""Граф достижимых блюд: «Дома» → «Купить X» → блюдо.

Узлы:
  home            — то, что уже есть дома;
  buy:<a>+<b>     — набор покупок (уникальный набор недостающих ингредиентов);
  dish:<id>       — блюдо.

Рёбра:
  home → dish             блюдо уровня 0;
  buy:S → dish            блюду не хватает ровно набора S;
  buy:T → buy:S           T ⊂ S и T — максимальное такое подмножество среди существующих наборов
                          («купил яйца — докупи ещё молоко»), у ребра есть поле add = S − T;
  home → buy:S            если подходящего подмножества нет.

Стоимость узла покупки — целыми упаковками на самое «жадное» блюдо узла
(если омлету нужно 110 г яиц, а сырникам 55 г, берём упаковки на 110 г).
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

from .core import DishOption
from .models import Catalog

HOME_ID = "home"


def purchase_node_id(items: frozenset[str]) -> str:
    return "buy:" + "+".join(sorted(items))


def dish_node_id(recipe_id: str) -> str:
    return "dish:" + recipe_id


def build_graph(options: Sequence[DishOption], catalog: Catalog) -> dict[str, Any]:
    """Строит JSON-граф из результата reachable_dishes"""

    sets: dict[frozenset[str], list[DishOption]] = {}
    for opt in options:
        if opt.missing:
            sets.setdefault(opt.missing, []).append(opt)

    # сколько граммов каждого ингредиента нужно докупить для узла
    need: dict[frozenset[str], dict[str, float]] = {
        s: {c: max(o.missing_g[c] for o in dishes) for c in s} for s, dishes in sets.items()
    }

    def items_of(s: frozenset[str], codes: frozenset[str]) -> list[dict[str, Any]]:
        return [
            {
                "code": c,
                "name": catalog.name(c),
                "packs": catalog.packs_needed(c, need[s][c]),
                "cost": catalog.pack_cost(c, need[s][c]),
            }
            for c in sorted(codes)
        ]

    def cost_of(s: frozenset[str], codes: frozenset[str]) -> float:
        return round(sum(catalog.pack_cost(c, need[s][c]) for c in codes), 2)

    def edge(src: str, dst: str, s: frozenset[str] | None = None, add: frozenset[str] = frozenset()) -> dict[str, Any]:
        e: dict[str, Any] = {"from": src, "to": dst}
        if s is not None and add:
            e["add"] = items_of(s, add)
            e["add_cost"] = cost_of(s, add)
        return e

    nodes: list[dict[str, Any]] = [{"id": HOME_ID, "type": "home", "level": 0}]
    edges: list[dict[str, Any]] = []

    for s in sorted(sets, key=lambda s: (len(s), cost_of(s, s), sorted(s))):
        nodes.append(
            {
                "id": purchase_node_id(s),
                "type": "purchase",
                "level": len(s),
                "items": items_of(s, s),
                "cost": cost_of(s, s),
                "dish_count": len(sets[s]),
            }
        )
        subsets = [t for t in sets if t < s]
        parents = [t for t in subsets if not any(t < u for u in subsets)]
        if parents:
            for t in sorted(parents, key=sorted):
                edges.append(edge(purchase_node_id(t), purchase_node_id(s), s, s - t))
        else:
            edges.append(edge(HOME_ID, purchase_node_id(s), s, s))

    for opt in options:
        m = opt.metrics
        nodes.append(
            {
                "id": dish_node_id(opt.recipe.id),
                "type": "dish",
                "level": opt.level,
                "recipe_id": opt.recipe.id,
                "title": opt.recipe.title,
                "cook_time_min": m.cook_time_min,
                "equipment": sorted(opt.recipe.equipment),
                "kcal": m.kcal,
                "protein": m.protein,
                "fat": m.fat,
                "carbs": m.carbs,
                "buy_cost": m.buy_cost,
                "portion_cost": m.portion_cost,
                "allergens": sorted(m.allergens),
            }
        )
        src = purchase_node_id(opt.missing) if opt.missing else HOME_ID
        edges.append(edge(src, dish_node_id(opt.recipe.id)))

    return {"nodes": nodes, "edges": edges}
