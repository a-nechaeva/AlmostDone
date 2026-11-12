from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from ..support.application import create_app
from ..support.http import FILTERS, auth, check, mutation
from ..support.catalog import custom_catalog


def test_unweighed_stock_uses_native_engine_semantics_and_portions():
    app = create_app()
    with TestClient(app) as client:
        headers = auth(app)
        for code in ("rice", "tomato"):
            client.post("/api/v1/me/pantry/add", json={"ingredient_id": code, "quantity": None}, headers=mutation(client, headers))
        card = check(app, client.get("/api/v1/recipes/rice_tomato?servings=2", headers=headers), "RecipeDetail")["recipe"]
        assert card["availability"] == {"status": "ready", "missing_count": 0, "unknown_quantity_ids": ["rice", "tomato"]}
        scaled = check(app, client.get("/api/v1/recipes/rice_tomato?servings=12", headers=headers), "RecipeDetail")
        assert scaled["recipe"]["servings"] == 12
        assert scaled["recipe"]["availability"]["status"] == "ready"
        assert scaled["recipe"]["buy_cost"] == {"minor_units": 0, "currency": "RUB"}
        assert scaled["recipe"]["nutrition_per_serving"] == card["nutrition_per_serving"]
        assert [item["required"]["value"] for item in scaled["ingredients"]] == [1200, 600]
        body = {"request_id": str(uuid4()), "servings": 2, "filters": {**FILTERS, "mode": "now"}, "visibility": "visible", "limit": 20}
        page = check(app, client.post("/api/v1/recommendations", json=body, headers=headers), "RecommendationPage", 201)
        assert [c["id"] for c in page["items"]] == ["rice_tomato"]
        graph = check(app, client.get("/api/v1/recommendations/" + page["snapshot_id"] + "/graph", headers=headers), "RecommendationGraph")["graph"]
        assert any(node.get("recipe_id") == "rice_tomato" and node["level"] == 0 for node in graph["nodes"])


def test_unknown_recipe_quantity_is_not_replaced_with_a_server_estimate():
    data = custom_catalog()
    data["recipes"][0]["items"][0]["qty_g"] = None
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        client.post("/api/v1/me/pantry/add", json={"ingredient_id": "rice", "quantity": None}, headers=mutation(client, headers))
        detail = check(app, client.get("/api/v1/recipes/rice_tomato", headers=headers), "RecipeDetail")
        assert detail["ingredients"][0]["required"] is None
        assert detail["ingredients"][0]["availability"] == "unknown"
        assert detail["ingredients"][0]["shortage"] is None
        assert detail["recipe"]["availability"]["status"] == "unknown"


@pytest.mark.parametrize("flags,equipment,included", [
    ({"needs_stove": True}, ["stove"], True),
    ({"needs_stove": True}, ["oven"], False),
    ({"needs_stove": False}, [], False),
    ({"needs_stove": False}, ["no_cook"], False),
    ({"needs_stove": False}, ["stove", "oven", "microwave"], True),
    ({"needs_stove": False, "no_cook": True}, [], True),
])
def test_equipment_filter_is_decided_by_ready_engine(flags, equipment, included):
    data = custom_catalog()
    data["recipes"] = [data["recipes"][0]]
    data["recipes"][0].update(flags)
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        body = {"request_id": str(uuid4()), "servings": 2, "filters": {**FILTERS, "equipment": equipment}, "visibility": "visible", "limit": 20}
        page = check(app, client.post("/api/v1/recommendations", json=body, headers=headers), "RecommendationPage", 201)
        assert bool(page["items"]) == included
