import pytest

from ..support.catalog import make_catalog
from almostdone_server.errors import APIError
from almostdone_server.services.models import default_user
from ..support.http import FILTERS
from ..support.catalog import custom_catalog


def request():
    return {"request_id": "id", "servings": 2, "filters": FILTERS,
            "budget": {"minor_units": 100000, "currency": "RUB"}}


def test_exact_budget_is_rejected_without_calling_greedy_engine_as_exact(monkeypatch):
    catalog = make_catalog(custom_catalog())
    def forbidden(*args, **kwargs):
        pytest.fail("The engine's greedy plan must not be presented as an exact maximum")
    monkeypatch.setattr(catalog.gateway.engine, "best_purchases", forbidden)
    with pytest.raises(APIError) as error:
        catalog.purchases(default_user(), request(), False)
    assert error.value.status == 503
    assert error.value.details[0]["field"] == "exact_budget_optimization"


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


def test_unaffordable_single_purchase_does_not_use_server_subset_optimizer():
    catalog, user = make_catalog(custom_catalog()), default_user()
    user["pantry"]["tomato"] = {"value": 2000, "unit": "g"}
    body = request()
    body["budget"]["minor_units"] = 100
    with pytest.raises(APIError) as error:
        catalog.purchases(user, body, True)
    assert error.value.status == 503
    assert error.value.details[0]["field"] == "budget_constrained_single_purchase"
