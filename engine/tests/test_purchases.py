import copy

import pytest

from dishgraph import CatalogError, best_purchases, best_single_purchases, catalog_from_dict, reachable_dishes

from .conftest import SMALL


def test_best_single(catalog):
    singles = best_single_purchases(reachable_dishes({"egg"}, catalog), catalog)
    assert singles[0].code == "milk"
    assert singles[0].packs == 1
    assert set(singles[0].unlocks) == {"omelette", "milk_drink"}


def test_budget_plan_greedy(catalog):
    options = reachable_dishes({"egg"}, catalog)
    plan = best_purchases(options, catalog, budget=1000)
    assert [s.buy for s in plan.steps] == [{"milk": 1}, {"flour": 1}, {"cheese": 1}]
    assert plan.total_cost == 340
    assert set(plan.unlocked) == {"omelette", "milk_drink", "pancakes", "cheese_pancakes"}


def test_budget_limits_plan(catalog):
    options = reachable_dishes({"egg"}, catalog)
    plan = best_purchases(options, catalog, budget=100)
    assert plan.items == {"milk": 1}
    assert plan.total_cost <= 100
    assert best_purchases(options, catalog, budget=0).steps == []


def test_plan_reuses_bought_packs(catalog):
    # без яиц и молока: одна упаковка яиц и одна молока закрывают сразу омлет, напиток и яйцо с зеленью
    plan = best_purchases(reachable_dishes(set(), catalog), catalog, budget=180)
    assert plan.items == {"egg": 1, "milk": 1}
    assert {"omelette", "milk_drink", "herb_egg"} <= set(plan.unlocked)


def test_plan_to_dict(catalog):
    d = best_purchases(reachable_dishes({"egg"}, catalog), catalog, budget=100).to_dict(catalog)
    assert d["total_cost"] == 80
    assert d["items"] == [{"code": "milk", "name": "Milk", "packs": 1, "cost": 80.0}]


# --- проверки каталога (повторяют ограничения схемы БД) --------------------------------

def broken(mutate):
    data = copy.deepcopy(SMALL)
    mutate(data)
    return data


@pytest.mark.parametrize(
    "mutate, message",
    [
        (lambda d: d["recipes"][0]["items"].append({"code": "unicorn", "qty_g": 1}), "unicorn"),
        (lambda d: d["ingredients"][1].update(code="Egg"), "Код ингредиента"),
        (lambda d: d["ingredients"][1].update(protein=60, fat=30, carbs=20), "БЖУ"),
        (lambda d: d["ingredients"][1].update(display_unit="pcs"), "grams_per_piece"),
        (lambda d: d["recipes"][0]["items"].append({"code": "egg", "qty_g": 5}), "дважды"),
        (lambda d: d["recipes"][1]["items"][0].update(is_optional=True), "нет обязательных"),
        (lambda d: d["ingredients"].append({**d["ingredients"][1], "code": "egg2", "name": "EGG"}), "Название"),
    ],
)
def test_catalog_validation(mutate, message):
    with pytest.raises(CatalogError, match=message):
        catalog_from_dict(broken(mutate))
