import copy

from fastapi.testclient import TestClient

from almostdone_server.main import create_app
from ..support.http import auth, check
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
        check(app, client.get('/api/v1/ingredients', params={'q': 'а' * 70}, headers=headers), 'Error', 503)
        check(app, client.get('/api/v1/ingredients', params={'q': '   '}, headers=headers), 'IngredientPage')
