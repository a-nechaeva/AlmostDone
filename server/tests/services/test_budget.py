import pytest

from ..support.catalog import make_catalog
from almostdone_server.services.models import default_user
from ..support.http import FILTERS
from ..support.catalog import custom_catalog


def request():
    return {"request_id": "id", "servings": 2, "filters": FILTERS,
            "budget": {"minor_units": 100000, "currency": "RUB"}}


def test_budget_projects_existing_engine_plan_and_converts_kopecks(monkeypatch):
    catalog, user = make_catalog(custom_catalog()), default_user()
    user["pantry"]["tomato"] = {"value": 2000, "unit": "g"}
    original, calls = catalog.gateway.engine.best_purchases, []
    def calculate(options, engine_catalog, budget):
        plan = original(options, engine_catalog, budget)
        calls.append((budget, plan))
        return plan
    monkeypatch.setattr(catalog.gateway.engine, "best_purchases", calculate)
    result = catalog.purchases(user, request(), False)
    assert len(calls) == 1
    budget, plan = calls[0]
    assert budget == 1000
    assert {item["ingredient_id"]: item["package_count"] for item in result["shopping_items"]} == plan.items
    assert result["unlocked_recipe_ids"] == list(plan.unlocked)
    assert result["total_cost"]["minor_units"] == round(plan.total_cost * 100)
    assert result["total_cost"]["minor_units"] <= request()["budget"]["minor_units"]
    assert result["semantics"] == "alternatives"
    assert result["status"] == "found"
    assert user["pantry"] == {"tomato": {"value": 2000, "unit": "g"}}
    assert user["version"] == 0


@pytest.mark.parametrize("budget", [0, 1, 100])
def test_budget_without_affordable_purchases_returns_no_plan(budget):
    catalog = make_catalog(custom_catalog())
    body = request()
    body["budget"]["minor_units"] = budget
    result = catalog.purchases(default_user(), body, False)
    assert result["status"] == "no_plan"
    assert result["shopping_items"] == []
    assert result["unlocked_recipe_ids"] == []
    assert result["total_cost"] is None


@pytest.mark.parametrize("single", [False, True])
def test_budget_reports_unpriced_recipes_without_treating_them_as_free(monkeypatch, single):
    catalog = make_catalog(custom_catalog())
    monkeypatch.setattr(catalog, "matches", lambda *args: [
        ({"recipe": {"id": "unknown", "suitability": {"status": "allowed"}}}, None),
    ])
    result = catalog.purchases(default_user(), request(), single)
    assert result["status"] == "insufficient_data"
    assert result["unpriced_recipe_ids"] == ["unknown"]
    if single:
        assert result["options"] == []
    else:
        assert result["shopping_items"] == []
        assert result["total_cost"] is None


def test_single_purchase_is_a_projection_of_existing_engine_result(monkeypatch):
    catalog, user = make_catalog(custom_catalog()), default_user()
    user["pantry"]["tomato"] = {"value": 2000, "unit": "g"}
    original, calls = catalog.gateway.engine.best_single_purchases, []
    def calculate(*args):
        result = original(*args)
        calls.append(result)
        return result
    monkeypatch.setattr(catalog.gateway.engine, "best_single_purchases", calculate)
    result = catalog.purchases(user, request(), True)
    assert len(calls) == 1
    assert [(o["shopping_item"]["ingredient_id"], o["shopping_item"]["package_count"], o["unlocked_recipe_ids"])
            for o in result["options"]] == [(s.code, s.packs, list(s.unlocks)) for s in calls[0]]


@pytest.mark.parametrize("budget", [0, 1, 9999])
def test_unaffordable_single_purchase_returns_no_plan(budget):
    catalog, user = make_catalog(custom_catalog()), default_user()
    user["pantry"]["tomato"] = {"value": 2000, "unit": "g"}
    body = request()
    body["budget"]["minor_units"] = budget
    result = catalog.purchases(user, body, True)
    assert result["status"] == "no_plan"
    assert result["options"] == []
    assert result["unpriced_recipe_ids"] == []


@pytest.mark.parametrize("servings,budget,status", [(2, 10001, "found"), (2, 10000, "no_plan"),
                                                   (6, 20002, "found"), (6, 20001, "no_plan")])
def test_single_purchase_budget_uses_whole_packages_and_kopecks(servings, budget, status):
    data = custom_catalog()
    data["ingredients"][0]["package_price"] = 100.01
    catalog, user = make_catalog(data), default_user()
    user["pantry"]["tomato"] = {"value": 2000, "unit": "g"}
    body = request()
    body["servings"] = servings
    body["budget"]["minor_units"] = budget
    result = catalog.purchases(user, body, True)
    assert result["status"] == status
    if status == "found":
        option, = result["options"]
        assert option["shopping_item"]["package_count"] == (1 if servings == 2 else 2)
        assert option["shopping_item"]["total_price"]["minor_units"] == budget
    else:
        assert result["options"] == []
