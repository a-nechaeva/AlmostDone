"""Рекомендации «что докупить». Покупаем целыми упаковками."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Any

from .core import DishOption
from .models import Catalog


@dataclass(frozen=True)
class SinglePurchase:
    code: str
    packs: int  # сколько упаковок взять, чтобы хватило на все открытые блюда
    price: float  # packs * цена упаковки
    unlocks: tuple[str, ...]  # id рецептов, которые станут доступны

    def to_dict(self, catalog: Catalog) -> dict[str, Any]:
        return {
            "code": self.code,
            "name": catalog.name(self.code),
            "packs": self.packs,
            "price": self.price,
            "unlocks": list(self.unlocks),
            "unlock_count": len(self.unlocks),
        }


def best_single_purchases(options: Sequence[DishOption], catalog: Catalog) -> list[SinglePurchase]:
    """Какой один ингредиент открывает больше всего блюд (по блюдам уровня 1)."""
    grams: dict[str, float] = {}
    unlocks: dict[str, list[str]] = {}
    for opt in options:
        if opt.level == 1:
            ((code, g),) = opt.missing_g.items()
            grams[code] = max(grams.get(code, 0.0), g)
            unlocks.setdefault(code, []).append(opt.recipe.id)

    result = [
        SinglePurchase(
            code=c,
            packs=catalog.packs_needed(c, grams[c]),
            price=catalog.pack_cost(c, grams[c]),
            unlocks=tuple(r),
        )
        for c, r in unlocks.items()
    ]
    result.sort(key=lambda p: (-len(p.unlocks), p.price, p.code))
    return result


@dataclass(frozen=True)
class PlanStep:
    buy: dict[str, int]  # код -> сколько упаковок докупить на этом шаге
    cost: float
    unlocks: tuple[str, ...]  # какие рецепты стали доступны после шага


@dataclass
class BudgetPlan:
    budget: float
    steps: list[PlanStep] = field(default_factory=list)

    @property
    def total_cost(self) -> float:
        return round(sum(s.cost for s in self.steps), 2)

    @property
    def items(self) -> dict[str, int]:
        """Итоговый список покупок: код -> упаковок."""
        total: dict[str, int] = {}
        for s in self.steps:
            for c, n in s.buy.items():
                total[c] = total.get(c, 0) + n
        return total

    @property
    def unlocked(self) -> tuple[str, ...]:
        return tuple(r for s in self.steps for r in s.unlocks)

    def to_dict(self, catalog: Catalog) -> dict[str, Any]:
        def lines(packs: dict[str, int]) -> list[dict[str, Any]]:
            return [
                {
                    "code": c,
                    "name": catalog.name(c),
                    "packs": n,
                    "cost": n * catalog.ingredients[c].package_price,
                }
                for c, n in sorted(packs.items())
            ]

        return {
            "budget": self.budget,
            "total_cost": self.total_cost,
            "items": lines(self.items),
            "unlocked": list(self.unlocked),
            "steps": [{"buy": lines(s.buy), "cost": s.cost, "unlocks": list(s.unlocks)} for s in self.steps],
        }


def best_purchases(options: Sequence[DishOption], catalog: Catalog, budget: float) -> BudgetPlan:
    """Жадно выбирает покупки в пределах бюджета, чтобы открыть как можно больше блюд.

    На каждом шаге перебираем ещё недоступные блюда: «докупить упаковки, которых не хватает этому
    блюду». Считаем, сколько блюд откроется вместе с ним (у других тоже может всё сойтись), и берём
    вариант с лучшим соотношением «новые блюда / рубли». Уже купленные упаковки учитываются:
    если для омлета взяли десяток яиц, сырникам яйца докупать не нужно.
    """
    plan = BudgetPlan(budget=budget)
    locked = [o for o in options if o.missing_g]
    bought: dict[str, int] = {}
    spent = 0.0

    def needed(opt: DishOption) -> dict[str, int]:
        return {c: catalog.packs_needed(c, g) for c, g in opt.missing_g.items()}

    def covered(opt: DishOption, packs: dict[str, int]) -> bool:
        return all(packs.get(c, 0) >= n for c, n in needed(opt).items())

    while locked:
        best = None
        for opt in locked:
            extra = {c: n - bought.get(c, 0) for c, n in needed(opt).items() if n > bought.get(c, 0)}
            cost = sum(n * catalog.ingredients[c].package_price for c, n in extra.items())
            if spent + cost > budget + 1e-9:
                continue
            after = {**bought, **{c: bought.get(c, 0) + n for c, n in extra.items()}}
            gained = [o for o in locked if covered(o, after)]
            ratio = len(gained) / cost if cost > 0 else float("inf")
            score = (ratio, len(gained), -cost)
            if best is None or score > best[0]:
                best = (score, extra, cost, gained, after)
        if best is None:
            break
        _, extra, cost, gained, after = best
        bought = after
        spent += cost
        plan.steps.append(PlanStep(buy=extra, cost=round(cost, 2), unlocks=tuple(o.recipe.id for o in gained)))
        gained_ids = {id(o) for o in gained}
        locked = [o for o in locked if id(o) not in gained_ids]

    return plan
