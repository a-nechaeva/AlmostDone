import pytest
from fastapi.testclient import TestClient

from almostdone_server.main import create_app
from ..support.http import auth, check
from ..support.catalog import custom_catalog


@pytest.mark.parametrize("partial", [False, True])
def test_step_metadata_is_preserved_for_complete_and_partial_recipes(partial):
    data = custom_catalog()
    recipe = data["recipes"][0]
    recipe["step_details"] = [{"number": 1, "text": "Prepare", "minutes": 5},
                              {"number": 3, "text": "Serve", "minutes": None}]
    if partial:
        data["ingredients"][0]["kcal"] = None
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        result = check(app, client.get("/api/v1/recipes/" + recipe["id"], headers=auth(app)), "RecipeDetail")
        assert result["steps"] == recipe["step_details"]
