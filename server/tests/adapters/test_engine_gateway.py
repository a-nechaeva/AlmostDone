"""The server delegates computations instead of implementing alternative rules."""
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from ..support.catalog import make_catalog
from almostdone_server.errors import APIError
from ..support.application import create_app
from almostdone_server.services.models import default_user
from ..support.http import FILTERS, auth, check
from ..support.catalog import custom_catalog


def test_recommendation_order_and_options_come_from_reachable_dishes(monkeypatch):
    catalog, user = make_catalog(custom_catalog()), default_user()
    original, calls = catalog.gateway.engine.reachable_dishes, []

    def calculate(*args, **kwargs):
        result = original(*args, **kwargs)
        calls.append(result)
        return result

    monkeypatch.setattr(catalog.gateway.engine, "reachable_dishes", calculate)
    result = catalog.matches(user, FILTERS, 2)
    assert len(calls) == 1
    assert [option for _, option in result] == calls[0]
    assert [detail["recipe"]["id"] for detail, _ in result] == [option.recipe.id for option in calls[0]]


def test_graph_calls_ready_engine_with_original_snapshot_options(monkeypatch):
    app = create_app()
    engine = app.state.service.catalog.gateway.engine
    original, calls = engine.build_graph, []

    def calculate(options, catalog):
        calls.append([option.recipe.id for option in options])
        return original(options, catalog)

    monkeypatch.setattr(engine, "build_graph", calculate)
    with TestClient(app) as client:
        headers = auth(app)
        body = {"request_id": str(uuid4()), "servings": 2, "filters": FILTERS, "visibility": "visible", "limit": 1}
        page = check(app, client.post("/api/v1/recommendations", json=body, headers=headers), "RecommendationPage", 201)
        graph = check(app, client.get("/api/v1/recommendations/" + page["snapshot_id"] + "/graph", headers=headers), "RecommendationGraph")["graph"]
        assert len(calls) == 1
        assert {node["recipe_id"] for node in graph["nodes"] if node["kind"] == "recipe"} == set(calls[0])
        assert "engine_options" not in page


def test_title_filter_selects_input_recipes_without_changing_engine_calculations(monkeypatch):
    catalog = make_catalog(custom_catalog())
    original, calls = catalog.gateway.engine.reachable_dishes, []
    def calculate(*args, **kwargs):
        result = original(*args, **kwargs)
        calls.append(result)
        return result
    monkeypatch.setattr(catalog.gateway.engine, "reachable_dishes", calculate)
    result = catalog.matches(default_user(), {**FILTERS, "q": "  РИС  "}, 2)
    assert [detail["recipe"]["id"] for detail, _ in result] == ["rice_tomato"]
    assert [option for _, option in result] == calls[0]


def test_unconvertible_stock_is_not_sent_to_engine_as_unlimited_presence():
    data = custom_catalog()
    data["ingredients"][0]["allowed_units"] = ["g", "ml"]
    user = default_user()
    user["pantry"]["rice"] = {"value": 100, "unit": "ml"}
    with pytest.raises(APIError) as error:
        make_catalog(data).detail("rice_tomato", user, 2)
    assert error.value.details[0]["field"] == "pantry_unit_conversion:rice"


def test_incomplete_allergen_data_is_reported_without_rejecting_the_recipe():
    catalog, user = make_catalog(custom_catalog()), default_user()
    user["preferences"]["excluded_allergens"] = ["milk"]
    detail, _ = catalog.detail("tomato_cheese", user, 2)
    assert detail["recipe"]["allergens"]["completeness"] == "incomplete"
    assert detail["recipe"]["suitability"]["status"] == "hidden"
    assert any(reason["code"] == "incomplete_allergen_data" for reason in detail["recipe"]["suitability"]["reasons"])


@pytest.mark.parametrize("quantity_present", [True, False])
def test_unknown_required_quantity_never_reaches_engine_calculations(monkeypatch, quantity_present):
    data = custom_catalog()
    item = data["recipes"][0]["items"][0]
    if quantity_present:
        item["qty_g"] = None
    else:
        item.pop("qty_g")
    catalog = make_catalog(data)
    user = default_user()
    user["pantry"]["rice"] = None
    assert "rice_tomato" in catalog.gateway.unsupported_recipes

    def unexpected_calculation(*args, **kwargs):
        raise AssertionError("Unknown required quantities must not be estimated by the engine")

    monkeypatch.setattr(catalog.gateway.engine, "dish_option", unexpected_calculation)
    detail, option = catalog.detail("rice_tomato", user, 2)
    assert option is None
    assert detail["recipe"]["availability"]["status"] == "unknown"
    assert detail["recipe"]["nutrition_per_serving"] is None
    assert detail["recipe"]["buy_cost"] is None
    assert detail["shopping_items"] == []


def test_requested_portions_survive_snapshot_serialization():
    from ..support.catalog import make_catalog, custom_catalog
    catalog = make_catalog(custom_catalog())
    gateway = catalog.gateway
    option, _ = gateway.detail('rice_tomato', {}, set(), servings=4)
    original = gateway.engine.dish_option(gateway.engine_catalog.recipe('rice_tomato'), {}, gateway.engine_catalog, servings=4)
    assert option.missing_g == original.missing_g
    assert option.metrics == original.metrics
    restored = gateway.restore_option(gateway.serialize_option(option))
    assert restored.portions == 4
    assert restored.missing_g == option.missing_g
    assert restored.metrics == option.metrics
