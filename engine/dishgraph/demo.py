"""Быстрая проверка руками: python -m dishgraph.demo [--json]"""

from __future__ import annotations

import json
import sys

from . import best_purchases, best_single_purchases, build_graph, load_catalog, reachable_dishes

# Кладовка: None — «есть, количество не указано»; число — граммы
DEMO_PANTRY = {
    "egg": 110,  # два яйца
    "milk": None,
    "potato": None,
    "onion": None,
    "pasta": None,
    "butter": None,
    "flour": None,
    "bread": None,
}


def main() -> None:
    catalog = load_catalog()
    options = reachable_dishes(DEMO_PANTRY, catalog)

    home = [catalog.name(c) + (f" {q:.0f} г" if q else "") for c, q in sorted(DEMO_PANTRY.items())]
    print("Дома:", ", ".join(home))
    print()
    for level in range(4):
        group = [o for o in options if o.level == level]
        if not group:
            continue
        print(f"=== Уровень {level} ===" if level else "=== Можно приготовить сейчас ===")
        for o in group:
            m = o.metrics
            buy = ", ".join(
                f"{catalog.name(c)} ×{catalog.packs_needed(c, g)}" for c, g in sorted(o.missing_g.items())
            )
            print(
                f"  {o.recipe.title:32} {m.cook_time_min:>3} мин  {m.kcal:>6} ккал  "
                f"порция {m.portion_cost:>5} ₽"
                + (f"  | докупить: {buy} ({m.buy_cost:.0f} ₽)" if buy else "")
            )
        print()

    print("=== Одна покупка, которая открывает больше всего ===")
    for p in best_single_purchases(options, catalog)[:5]:
        print(
            f"  {catalog.name(p.code)} ×{p.packs} ({p.price:.0f} ₽) → +{len(p.unlocks)}: {', '.join(p.unlocks)}"
        )
    print()

    plan = best_purchases(options, catalog, budget=500)
    print(f"=== Лучшие покупки на {plan.budget:.0f} ₽ (потрачено {plan.total_cost:.0f} ₽) ===")
    for s in plan.steps:
        buy = ", ".join(f"{catalog.name(c)} ×{n}" for c, n in sorted(s.buy.items()))
        print(f"  купить {buy} ({s.cost:.0f} ₽) → {', '.join(s.unlocks)}")
    print()

    micro = reachable_dishes(DEMO_PANTRY, catalog, equipment={"microwave"})
    print("Только микроволновка:", ", ".join(o.recipe.title for o in micro) or "ничего")

    graph = build_graph(options, catalog)
    print(f"Граф: {len(graph['nodes'])} узлов, {len(graph['edges'])} рёбер")
    if "--json" in sys.argv:
        print(json.dumps(graph, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
