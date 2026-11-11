from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from almostdone_server.main import create_app
from ..support.http import FILTERS, auth, check, mutation
from ..support.catalog import custom_catalog


@pytest.mark.parametrize("field", ["package_price", "kcal", "protein", "fat", "carbs", "package_g"])
def test_incomplete_data_remains_searchable_but_is_not_calculated_by_server(field):
    data = custom_catalog()
    data["ingredients"][0][field] = None
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        check(app, client.get("/api/v1/ingredients", params={"q": "рис"}, headers=headers), "IngredientPage")
        response = client.get("/api/v1/recipes/rice_tomato", headers=headers)
        result = check(app, response, "RecipeDetail")
        assert result["recipe"]["availability"]["status"] == "unknown"
        assert result["recipe"]["nutrition_per_serving"] is None
        assert result["recipe"]["buy_cost"] is None
        assert result["shopping_items"] == []
        body = {"request_id": str(uuid4()), "servings": 2, "filters": FILTERS, "visibility": "visible", "limit": 20}
        page = check(app, client.post("/api/v1/recommendations", json=body, headers=headers), "RecommendationPage", 201)
        cards = {card["id"]: card for card in page["items"]}
        assert set(cards) == {"rice_tomato", "tomato_cheese"}
        assert cards["rice_tomato"]["availability"]["status"] == "unknown"
        assert cards["tomato_cheese"]["buy_cost"] is not None
        graph = check(app, client.get("/api/v1/recommendations/" + page["snapshot_id"] + "/graph", headers=headers), "RecommendationGraph")["graph"]
        assert graph["unrepresented_recipe_ids"] == ["rice_tomato"]
        assert [node["recipe_id"] for node in graph["nodes"] if node["kind"] == "recipe"] == ["tomato_cheese"]
        # An independent complete recipe is still served by the real engine.
        check(app, client.get("/api/v1/recipes/tomato_cheese", headers=headers), "RecipeDetail")


@pytest.mark.parametrize("field,value", [("qty_g", None), ("cook_time_min", None), ("cook_time_min", 0)])
def test_missing_recipe_values_are_returned_without_fallback_math(field, value):
    data = custom_catalog()
    if field == "qty_g":
        data["recipes"][0]["items"][0][field] = value
    else:
        data["recipes"][0][field] = value
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        detail = check(app, client.get("/api/v1/recipes/rice_tomato", headers=auth(app)), "RecipeDetail")
        assert detail["recipe"]["availability"]["status"] == "unknown"
        assert detail["recipe"]["buy_cost"] is None
        assert detail["recipe"]["nutrition_per_serving"] is None
        if field == "qty_g":
            assert detail["ingredients"][0]["required"] is None
            assert detail["ingredients"][0]["shortage"] is None
        else:
            assert detail["recipe"]["minutes"] is None


@pytest.mark.parametrize("mode", ["now", "buy_1_3"])
def test_partial_recipes_do_not_block_availability_dependent_modes(mode):
    data = custom_catalog()
    data["recipes"][0]["items"][0]["qty_g"] = None
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        if mode == "now":
            for code in ("tomato", "cheese"):
                assert client.post("/api/v1/me/pantry/add", json={"ingredient_id": code, "quantity": None},
                                   headers=mutation(client, headers)).status_code == 200
        body = {"request_id": str(uuid4()), "servings": 2, "filters": {**FILTERS, "mode": mode}, "visibility": "visible", "limit": 20}
        page = check(app, client.post("/api/v1/recommendations", json=body, headers=headers), "RecommendationPage", 201)
        assert [card["id"] for card in page["items"]] == ["tomato_cheese"]


@pytest.mark.parametrize("filters", [
    {**FILTERS, "max_minutes": 30},
    {**FILTERS, "max_kcal_per_serving": 1000},
    {**FILTERS, "equipment": []},
])
def test_partial_recipe_does_not_satisfy_unconfirmed_filters(filters):
    data = custom_catalog()
    data["recipes"][0]["cook_time_min"] = None
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        body = {"request_id": str(uuid4()), "servings": 2, "filters": filters, "visibility": "visible", "limit": 20}
        page = check(app, client.post("/api/v1/recommendations", json=body, headers=auth(app)), "RecommendationPage", 201)
        assert [card["id"] for card in page["items"]] == ["tomato_cheese"]


def test_mixed_servings_preserve_records_and_original_calculations():
    data = custom_catalog()
    data["recipes"][0]["servings"] = 4
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        for servings, calculated_id, unknown_id in [(2, "tomato_cheese", "rice_tomato"), (4, "rice_tomato", "tomato_cheese")]:
            body = {"request_id": str(uuid4()), "servings": servings, "filters": FILTERS, "visibility": "visible", "limit": 20}
            page = check(app, client.post("/api/v1/recommendations", json=body, headers=headers), "RecommendationPage", 201)
            cards = {card["id"]: card for card in page["items"]}
            assert set(cards) == {"rice_tomato", "tomato_cheese"}
            assert cards[calculated_id]["buy_cost"] is not None
            assert cards[unknown_id]["buy_cost"] is None
            assert cards[unknown_id]["availability"]["status"] == "unknown"
            detail = check(app, client.get("/api/v1/recipes/" + unknown_id, params={"servings": servings}, headers=headers), "RecipeDetail")
            assert detail["recipe"] == cards[unknown_id]
            assert all(item["required"] is None for item in detail["ingredients"])


def test_partial_recipe_is_not_lost_across_pages_or_presented_as_a_purchase():
    data = custom_catalog()
    data["ingredients"][0]["package_price"] = None
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        body = {"request_id": str(uuid4()), "servings": 2, "filters": FILTERS, "visibility": "visible", "limit": 1}
        first = check(app, client.post("/api/v1/recommendations", json=body, headers=headers), "RecommendationPage", 201)
        path = "/api/v1/recommendations/" + first["snapshot_id"]
        second = check(app, client.get(path, params={"cursor": first["page"]["next_cursor"]}, headers=headers), "RecommendationPage")
        assert [card["id"] for card in first["items"] + second["items"]] == ["tomato_cheese", "rice_tomato"]
        purchase = {"request_id": str(uuid4()), "servings": 2, "filters": FILTERS, "budget": {"minor_units": 100000, "currency": "RUB"}}
        result = check(app, client.post("/api/v1/recommendations/single-purchase", json=purchase, headers=headers), "SinglePurchaseResult")
        assert result["status"] == "insufficient_data"
        assert result["options"] == []
        assert result["unpriced_recipe_ids"] == ["rice_tomato"]


def test_unknown_allergen_completeness_is_visible_as_a_warning():
    data = custom_catalog()
    data["recipes"][0]["items"][0]["qty_g"] = None
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        body = {"request_id": str(uuid4()), "servings": 2, "filters": {**FILTERS, "exclude_allergens": ["milk"]}, "visibility": "visible", "limit": 20}
        page = check(app, client.post("/api/v1/recommendations", json=body, headers=headers), "RecommendationPage", 201)
        card, = page["items"]
        assert card["id"] == "rice_tomato"
        assert card["suitability"]["status"] == "unknown"
        assert page["unknown_total"] == 1
        assert page["hidden_total"] == 1
        detail = check(app, client.get("/api/v1/recipes/rice_tomato", params={"exclude_allergens": "milk"}, headers=headers), "RecipeDetail")
        assert detail["recipe"] == card


def test_unknown_optional_quantity_does_not_block_required_ingredient_calculations():
    data = custom_catalog()
    baseline = create_app(catalog_data=data)
    with TestClient(baseline) as client:
        original = check(baseline, client.get("/api/v1/recipes/rice_tomato", headers=auth(baseline)), "RecipeDetail")
    data["recipes"][0]["items"].append({"code": "cheese", "qty_g": None, "is_optional": True})
    app = create_app(catalog_data=data)
    assert "rice_tomato" not in app.state.service.catalog.gateway.unsupported_recipes
    with TestClient(app) as client:
        detail = check(app, client.get("/api/v1/recipes/rice_tomato", headers=auth(app)), "RecipeDetail")
        assert detail["recipe"]["availability"] == original["recipe"]["availability"]
        assert detail["recipe"]["buy_cost"] == original["recipe"]["buy_cost"]
        assert detail["recipe"]["nutrition_per_serving"] == original["recipe"]["nutrition_per_serving"]
        optional = next(item for item in detail["ingredients"] if item["ingredient_id"] == "cheese")
        assert optional["required"] is None
        assert optional["shortage"] is None
        assert optional["availability"] == "optional"
        assert optional["optional"] is True
        assert detail["recipe"]["allergens"]["contains"] == ["milk"]
        assert detail["shopping_items"] == original["shopping_items"]


def test_catalogue_with_no_calculable_recipes_still_has_a_valid_page_and_graph():
    data = custom_catalog()
    data["recipes"] = data["recipes"][:1]
    data["recipes"][0]["items"][0]["qty_g"] = None
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        body = {"request_id": str(uuid4()), "servings": 2, "filters": FILTERS, "visibility": "visible", "limit": 20}
        page = check(app, client.post("/api/v1/recommendations", json=body, headers=headers), "RecommendationPage", 201)
        assert [card["id"] for card in page["items"]] == ["rice_tomato"]
        graph = check(app, client.get("/api/v1/recommendations/" + page["snapshot_id"] + "/graph", headers=headers), "RecommendationGraph")["graph"]
        assert graph["nodes"] == [{"id": "home", "level": 0, "kind": "home", "label": "Дома"}]
        assert graph["edges"] == []
        assert graph["unrepresented_recipe_ids"] == ["rice_tomato"]
