import copy
from uuid import uuid4

from fastapi.testclient import TestClient

from ..support.application import create_app
from ..support.http import FILTERS, auth, check, mutation
from ..support.catalog import custom_catalog


def test_full_graph_preserves_chains_counts_and_long_recipe_ids_across_pages():
    data = custom_catalog()
    for code in ("flour", "milk", "unknown"):
        data["ingredients"].append({**copy.deepcopy(data["ingredients"][0]), "code": code, "name": code})
    template = copy.deepcopy(data["recipes"][0])
    recipe_specs = [
        ("r" * 128, [("tomato", 100)]),
        ("one", [("rice", 100)]),
        ("one_again", [("rice", 200)]),
        ("two", [("rice", 100), ("cheese", 100)]),
        ("three", [("rice", 100), ("cheese", 100), ("flour", 100)]),
        ("four", [("rice", 100), ("cheese", 100), ("flour", 100), ("milk", 100)]),
    ]
    data["recipes"] = [{**copy.deepcopy(template), "id": rid,
                        "items": [{"code": code, "qty_g": qty} for code, qty in ingredients]}
                       for rid, ingredients in recipe_specs]
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        for code, quantity in (("tomato", {"value": 2000, "unit": "g"}),):
            assert client.post("/api/v1/me/pantry/add", headers=mutation(client, headers),
                               json={"ingredient_id": code, "quantity": quantity}).status_code == 200
        request = {"request_id": str(uuid4()), "servings": 2, "filters": FILTERS,
                   "visibility": "visible", "limit": 1}
        page = check(app, client.post("/api/v1/recommendations", json=request, headers=headers), "RecommendationPage", 201)
        path = "/api/v1/recommendations/" + page["snapshot_id"]
        result = check(app, client.get(path + "/graph", headers=headers), "RecommendationGraph")
        graph = result["graph"]
        assert graph["unrepresented_recipe_ids"] == ["four"]
        nodes = {node["id"]: node for node in graph["nodes"]}
        assert len(nodes) == len(graph["nodes"])
        assert len([n for n in nodes.values() if n["kind"] == "recipe"]) == 5
        purchases = {n["level"]: n for n in nodes.values() if n["kind"] == "purchase"}
        assert set(purchases) == {1, 2, 3}
        assert purchases[1]["dish_count"] == 2
        for edge in graph["edges"]:
            assert edge["source"] in nodes and edge["target"] in nodes
            if edge["kind"] != "extends":
                continue
            source = nodes[edge["source"]]
            target = nodes[edge["target"]]
            stock = {i["ingredient_id"]: i["package_count"] for i in source.get("shopping_items", [])}
            for item in edge["add"]:
                assert item["package_count"] > 0
                stock[item["ingredient_id"]] = stock.get(item["ingredient_id"], 0) + item["package_count"]
            assert stock == {i["ingredient_id"]: i["package_count"] for i in target["shopping_items"]}
            assert edge["add_cost"]["minor_units"] == sum(i["total_price"]["minor_units"] for i in edge["add"])
        assert any(e["source"] == purchases[1]["id"] and e["target"] == purchases[2]["id"] for e in graph["edges"])
        assert any(e["source"] == purchases[2]["id"] and e["target"] == purchases[3]["id"] for e in graph["edges"])
        second = check(app, client.get(path, params={"cursor": page["page"]["next_cursor"]}, headers=headers), "RecommendationPage")
        assert second["items"][0]["id"] != page["items"][0]["id"]
        assert client.get(path + "/graph", headers=headers).json() == result


def test_scaled_snapshot_preserves_portions_and_package_counts():
    data = custom_catalog()
    data['ingredients'][0]['package_g'] = 100
    app = create_app(catalog_data=data)
    with TestClient(app) as client:
        headers = auth(app)
        client.post('/api/v1/me/pantry/add', headers=mutation(client, headers),
                    json={'ingredient_id': 'tomato', 'quantity': None})
        request = {'request_id': str(uuid4()), 'servings': 4, 'filters': FILTERS,
                   'visibility': 'visible', 'limit': 1}
        page = check(app, client.post('/api/v1/recommendations', json=request, headers=headers), 'RecommendationPage', 201)
        path = '/api/v1/recommendations/' + page['snapshot_id']
        graph = check(app, client.get(path + '/graph', headers=headers), 'RecommendationGraph')
        assert graph['servings'] == 4
        purchases = [item for node in graph['graph']['nodes'] if node['kind'] == 'purchase' for item in node['shopping_items']]
        rice = next(item for item in purchases if item['ingredient_id'] == 'rice')
        assert rice['package_count'] == 4
        assert all(node['recipe']['servings'] == 4 for node in graph['graph']['nodes'] if node['kind'] == 'recipe')
        second = check(app, client.get(path, params={'cursor': page['page']['next_cursor']}, headers=headers), 'RecommendationPage')
        assert all(card['servings'] == 4 and card['nutrition_per_serving'] is not None for card in page['items'] + second['items'])
        assert client.get(path + '/graph', headers=headers).json() == graph
