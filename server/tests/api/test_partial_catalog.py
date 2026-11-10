from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from almostdone_server.main import create_app
from ..support.http import FILTERS, auth, check
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
        result = check(app, response, "Error", 503)
        assert result["error"]["details"][0]["code"] == "engine_capability_missing"
        body = {"request_id": str(uuid4()), "servings": 2, "filters": FILTERS, "visibility": "visible", "limit": 20}
        check(app, client.post("/api/v1/recommendations", json=body, headers=headers), "Error", 503)
        # An independent complete recipe is still served by the real engine.
        check(app, client.get("/api/v1/recipes/tomato_cheese", headers=headers), "RecipeDetail")


@pytest.mark.parametrize("field,value", [("qty_g", None), ("cook_time_min", None), ("cook_time_min", 0)])
def test_missing_recipe_values_are_rejected_without_fallback_math(field, value):
    data = custom_catalog()
    if field == "qty_g":
        data["recipes"][0]["items"][0][field] = value
    else:
        data["recipes"][0][field] = value
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        check(app, client.get("/api/v1/recipes/rice_tomato", headers=auth(app)), "Error", 503)
