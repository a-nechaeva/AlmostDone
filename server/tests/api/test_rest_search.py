import copy

import pytest

from fastapi.testclient import TestClient

from ..support.application import create_app
from ..support.http import FILTERS, auth, check, mutation
from ..support.catalog import custom_catalog


def test_search_uses_typos_aliases_and_yo_normalization():
    data = custom_catalog()
    template = data["ingredients"][0]
    data["ingredients"] += [
        {**copy.deepcopy(template), "code": "milk", "name": "Молоко", "aliases": ["молочко"]},
        {**copy.deepcopy(template), "code": "honey", "name": "Мёд", "aliases": []},
    ]
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        for query, code in (("малако", "milk"), ("молочко", "milk"), ("  МЕД  ", "honey")):
            result = check(app, client.get("/api/v1/ingredients", params={"q": query}, headers=headers), "IngredientPage")
            assert result["items"][0]["id"] == code


def test_search_preserves_engine_ranking_across_api_pages():
    data = custom_catalog()
    template = data["ingredients"][0]
    data["ingredients"] += [{**copy.deepcopy(template), "code": f"item_{i:02}",
                             "name": "Тестовый продукт " + "а" * (20 - i), "aliases": []}
                            for i in range(18)]
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        params, ids = {"q": "тестовый", "limit": 3}, []
        while True:
            result = check(app, client.get("/api/v1/ingredients", params=params, headers=headers), "IngredientPage")
            ids.extend(item["id"] for item in result["items"])
            if not result["page"]["has_more"]:
                break
            params["cursor"] = result["page"]["next_cursor"]
        expected = app.state.service.catalog.search("тестовый")
        assert ids == expected and len(ids) == 18


def test_long_search_is_rejected_instead_of_using_a_server_fallback():
    app = create_app()
    with TestClient(app) as client:
        headers = auth(app)
        check(app, client.get('/api/v1/ingredients', params={'q': 'а' * 70}, headers=headers), 'Error', 422)
        check(app, client.get('/api/v1/ingredients', params={'q': 'а' * 64}, headers=headers), 'IngredientPage')
        check(app, client.get('/api/v1/ingredients', params={'q': '   '}, headers=headers), 'IngredientPage')


@pytest.mark.parametrize('unit', ['g', 'ml', 'pcs'])
def test_nutrition_is_shared_by_search_favorites_and_catalog(unit):
    data = custom_catalog()
    ingredient = data['ingredients'][0]
    ingredient.update(display_unit=unit, grams_per_piece=50, grams_per_ml=1,
                      kcal=123.4, protein=5.6, fat=7.8, carbs=9.1)
    expected = {'kcal': 123.4, 'protein_g': 5.6, 'fat_g': 7.8, 'carbs_g': 9.1}
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        response = client.get('/api/v1/ingredients', params={'q': ingredient['name']}, headers=headers)
        assert response.status_code == 200, response.text
        found = next(item for item in response.json()['items'] if item['id'] == ingredient['code'])
        assert found['nutrition_per_100g'] == expected
        response = client.put('/api/v1/me/favorites/ingredients/' + ingredient['code'],
                              headers=mutation(client, headers))
        assert response.status_code == 200, response.text
        response = client.get('/api/v1/me/favorites/ingredients', headers=headers)
        assert response.status_code == 200, response.text
        assert response.json()['items'][0]['nutrition_per_100g'] == expected
        response = client.get('/api/v1/catalog', headers=headers)
        assert response.status_code == 200, response.text
        found = next(item for item in response.json()['ingredients'] if item['id'] == ingredient['code'])
        assert found['nutrition_per_100g'] == expected


def test_missing_nutrition_is_null_instead_of_fabricated_zeroes():
    data = custom_catalog()
    ingredient = data['ingredients'][0]
    ingredient.pop('protein')
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        response = client.get('/api/v1/ingredients', params={'q': ingredient['name']}, headers=headers)
        assert response.status_code == 200, response.text
        found = next(item for item in response.json()['items'] if item['id'] == ingredient['code'])
        assert found['nutrition_per_100g'] is None
        response = client.get('/api/v1/catalog', headers=headers)
        assert response.status_code == 200, response.text
        found = next(item for item in response.json()['ingredients'] if item['id'] == ingredient['code'])
        assert found['nutrition_per_100g'] is None


@pytest.mark.parametrize('value', [None, -1, float('nan'), float('inf')])
def test_invalid_source_values_do_not_produce_invalid_json(value):
    app = create_app(catalog_data=custom_catalog())
    catalog = app.state.service.catalog
    catalog.ingredients['rice']['kcal'] = value
    assert catalog.ingredient_nutrition('rice') is None


def test_zero_nutrition_is_known_data():
    app = create_app(catalog_data=custom_catalog())
    catalog = app.state.service.catalog
    catalog.ingredients['rice'].update(kcal=0, protein=0, fat=0, carbs=0)
    assert catalog.ingredient_nutrition('rice') == {
        'kcal': 0, 'protein_g': 0, 'fat_g': 0, 'carbs_g': 0,
    }


@pytest.mark.parametrize("query,expected", [("  РИС   С ТОМАТАМИ ", ["rice_tomato"]),
                                           ("тёплый", ["rice_tomato"]), ("несуществующий", []),
                                           ("   ", ["rice_tomato", "tomato_cheese"])])
@pytest.mark.parametrize("partial", [False, True])
def test_recipe_title_search_includes_partial_catalog_and_preserves_pagination(query, expected, partial):
    from uuid import uuid4
    data = custom_catalog()
    data["recipes"][0]["title"] = "Теплый рис с томатами"
    if partial:
        data["recipes"][0]["items"][0]["qty_g"] = None
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        body = {"request_id": str(uuid4()), "servings": 2, "filters": {**FILTERS, "q": query},
                "visibility": "visible", "limit": 1}
        page = check(app, client.post("/api/v1/recommendations", json=body, headers=headers), "RecommendationPage", 201)
        ids = [item["id"] for item in page["items"]]
        while page["page"]["has_more"]:
            page = check(app, client.get("/api/v1/recommendations/" + page["snapshot_id"],
                         params={"cursor": page["page"]["next_cursor"]}, headers=headers), "RecommendationPage")
            ids.extend(item["id"] for item in page["items"])
        assert set(ids) == set(expected)
        purchase = {key: body[key] for key in ("request_id", "servings", "filters")}
        purchase["budget"] = {"minor_units": 100000, "currency": "RUB"}
        for endpoint, schema in (("budget", "PurchaseResult"), ("single-purchase", "SinglePurchaseResult")):
            result = check(app, client.post("/api/v1/recommendations/" + endpoint, json=purchase, headers=headers), schema)
            unlocked = (result["unlocked_recipe_ids"] if endpoint == "budget" else
                        [rid for option in result["options"] for rid in option["unlocked_recipe_ids"]])
            assert set(unlocked) <= set(expected)
            assert set(result["unpriced_recipe_ids"]) <= set(expected)


def test_ml_quantity_uses_density_for_recipe_shortages_and_package_units():
    data = custom_catalog()
    data["ingredients"][0].update(display_unit="ml", grams_per_ml=0.92)
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        ingredients = check(app, client.get("/api/v1/ingredients", params={"q": data["ingredients"][0]["name"]}, headers=headers), "IngredientPage")
        rice = next(item for item in ingredients["items"] if item["id"] == "rice")
        assert rice["allowed_units"] == ["g", "ml"]
        response = client.post("/api/v1/me/pantry/add", json={"ingredient_id": "rice",
                               "quantity": {"value": 100, "unit": "ml"}}, headers=mutation(client, headers))
        check(app, response, "Pantry")
        detail = check(app, client.get("/api/v1/recipes/rice_tomato", headers=headers), "RecipeDetail")
        rice = next(item for item in detail["ingredients"] if item["ingredient_id"] == "rice")
        assert rice["required"] == {"value": round(200 / 0.92, 6), "unit": "ml"}
        assert rice["shortage"] == {"value": round(108 / 0.92, 6), "unit": "ml"}
        assert rice["offer"]["quantity"] == {"value": round(500 / 0.92, 6), "unit": "ml"}
