from collections import deque

import pytest

from .conftest import JPEG, assert_contract, make_client

API = "/api/v1"


def ok(response, status=200):
    assert response.status_code == status, response.text
    return response.json()


# --- служебное и справочники -------------------------------------------------------------------

def test_health(client):
    assert ok(client.get(f"{API}/health")) == {"status": "ok", "api_version": "v1"}


def test_real_catalog_loaded(client):
    info = ok(client.get(f"{API}/debug/catalog"))
    assert info["source"] == "seed:seed.sql"
    assert info["recipes"] == 406 and info["ingredients"] == 851


def test_me_state_and_allergens(client):
    assert_contract(ok(client.get(f"{API}/me/state")), "State")
    body = ok(client.get(f"{API}/allergens"))
    assert_contract(body, "Dictionary")
    assert {"id": "milk", "name": "Молоко", "support": "supported"} in body["items"]


def test_openapi_docs(client):
    assert ok(client.get("/openapi.json"))["info"]["title"].startswith("Почти готово")


# --- поиск и кладовка -------------------------------------------------------------------------

def test_ingredient_search(client):
    body = ok(client.get(f"{API}/ingredients", params={"q": "малако", "limit": 5}))
    assert_contract(body, "IngredientPage")
    assert body["items"][0]["name"] == "Молоко"


def test_ingredient_search_paging(client):
    first = ok(client.get(f"{API}/ingredients", params={"q": "м", "limit": 3}))
    assert len(first["items"]) == 3 and first["page"]["has_more"]
    second = ok(client.get(f"{API}/ingredients", params={"q": "м", "limit": 3, "cursor": first["page"]["next_cursor"]}))
    assert {i["id"] for i in first["items"]}.isdisjoint(i["id"] for i in second["items"])


def test_demo_pantry_preloaded(client):
    body = ok(client.get(f"{API}/me/pantry"))
    assert_contract(body, "Pantry")
    assert len(body["items"]) == 19 and all(i["quantity"] is None for i in body["items"])


def test_pantry_crud(codes):
    c = make_client(demo_pantry=False)
    egg, milk = codes["Яйцо куриное"], codes["Молоко"]
    body = ok(c.post(f"{API}/me/pantry/add", json={"ingredient_id": egg, "quantity": {"value": 2, "unit": "pcs"}}))
    assert_contract(body, "Pantry")
    body = ok(c.post(f"{API}/me/pantry/add", json={"ingredient_id": egg, "quantity": {"value": 3, "unit": "pcs"}}))
    assert body["items"] == [{"ingredient_id": egg, "name": "Яйцо куриное", "quantity": {"value": 5, "unit": "pcs"}}]
    ok(c.put(f"{API}/me/pantry/{milk}", json={"quantity": None}))
    ok(c.put(f"{API}/me/pantry/{egg}", json={"quantity": {"value": 0, "unit": "pcs"}}))  # 0 удаляет
    body = ok(c.get(f"{API}/me/pantry"))
    assert [i["ingredient_id"] for i in body["items"]] == [milk]
    ok(c.delete(f"{API}/me/pantry/{milk}"))
    assert ok(c.get(f"{API}/me/pantry"))["items"] == []
    assert body["state_version"] >= 3


def test_pantry_errors(client, codes):
    r = client.post(f"{API}/me/pantry/add", json={"ingredient_id": "unicorn", "quantity": None})
    assert r.status_code == 422 and r.json()["error"]["code"] == "validation_error"
    assert_contract(r.json(), "Error")
    salt = codes["Соль"]
    r = client.post(f"{API}/me/pantry/add", json={"ingredient_id": salt, "quantity": {"value": 2, "unit": "pcs"}})
    assert r.status_code == 409 and r.json()["error"]["code"] == "unit_conflict"
    egg = codes["Яйцо куриное"]
    dup = [{"ingredient_id": egg, "quantity": {"value": 1, "unit": "pcs"}}] * 2
    r = client.post(f"{API}/me/pantry/purchased", json={"items": dup})
    assert r.status_code == 422


# --- подбор и граф ----------------------------------------------------------------------------

def recommend(client, **filters):
    body = {"servings": 2, "request_id": "00000000-0000-4000-8000-000000000001", "visibility": "visible",
            "limit": 10, "filters": {"q": "", "mode": "all", "max_minutes": None, "max_kcal_per_serving": None,
                                     "equipment": ["stove", "oven", "microwave", "no_cook"], "exclude_allergens": [],
                                     **filters}}
    return ok(client.post(f"{API}/recommendations", json=body), 201)


def test_recommendations(client):
    body = recommend(client)
    assert_contract(body, "RecommendationPage")
    assert body["visible_total"] >= 20 and len(body["items"]) == 10 and body["page"]["has_more"]
    levels = [i["availability"]["missing_count"] for i in body["items"]]
    assert levels == sorted(levels) and levels[0] == 0  # демо-кладовка: есть готовые блюда
    ready = body["items"][0]
    assert ready["availability"]["status"] == "ready" and ready["photo_url"].startswith("https://")


def test_recommendations_paging(client):
    first = recommend(client)
    second = ok(client.get(f"{API}/recommendations/{first['snapshot_id']}", params={"cursor": first["page"]["next_cursor"]}))
    assert_contract(second, "RecommendationPage")
    assert {i["id"] for i in first["items"]}.isdisjoint(i["id"] for i in second["items"])


def test_recommendations_modes_and_filters(client):
    now = recommend(client, mode="now")
    assert now["items"] and all(i["availability"]["missing_count"] == 0 for i in now["items"])
    buy = recommend(client, mode="buy_1_3")
    assert all(1 <= i["availability"]["missing_count"] <= 3 for i in buy["items"])
    no_milk = recommend(client, exclude_allergens=["milk"])
    assert all("milk" not in i["allergens"]["contains"] for i in no_milk["items"])
    micro = recommend(client, equipment=["microwave", "no_cook"])
    assert all(i["methods"] in (["no_cook"], ["microwave"]) for i in micro["items"])


def test_graph(client):
    snap = recommend(client)
    body = ok(client.get(f"{API}/recommendations/{snap['snapshot_id']}/graph"))
    assert_contract(body, "RecommendationGraph")
    g = body["graph"]
    ids = [n["id"] for n in g["nodes"]]
    assert len(ids) == len(set(ids)) and [n for n in g["nodes"] if n["kind"] == "home"][0]["level"] == 0
    assert any(e["kind"] == "extends" for e in g["edges"]) and any(e["kind"] == "unlocks" for e in g["edges"])
    out = {}
    for e in g["edges"]:
        assert e["source"] in ids and e["target"] in ids
        out.setdefault(e["source"], []).append(e["target"])
    seen, queue = {"home"}, deque(["home"])
    while queue:
        for t in out.get(queue.popleft(), []):
            if t not in seen:
                seen.add(t), queue.append(t)
    assert seen == set(ids)  # всё достижимо из home
    recipes = {n["recipe_id"] for n in g["nodes"] if n["kind"] == "recipe"}
    assert len(recipes) == snap["visible_total"]  # граф всего снимка, а не страницы


def test_unknown_snapshot(client):
    r = client.get(f"{API}/recommendations/snap-nope/graph")
    assert r.status_code == 404 and r.json()["error"]["code"] == "not_found"


# --- рецепт ------------------------------------------------------------------------------------

def test_recipe_detail_and_servings(client):
    rid = recommend(client, mode="buy_1_3")["items"][0]["id"]
    two = ok(client.get(f"{API}/recipes/{rid}", params={"servings": 2}))
    assert_contract(two, "RecipeDetail")
    assert two["steps"] and two["shopping_items"]
    assert any(i["availability"] == "missing" for i in two["ingredients"])
    six = ok(client.get(f"{API}/recipes/{rid}", params={"servings": 6}))
    req = lambda d: {i["ingredient_id"]: i["required"] for i in d["ingredients"] if i["required"]}  # noqa: E731
    for code, q in req(six).items():
        assert q["value"] == pytest.approx(req(two)[code]["value"] * 3, rel=1e-3)
    assert six["recipe"]["servings"] == 6


def test_recipe_detail_excluded_allergen(client):
    rid = next(i["id"] for i in recommend(client)["items"] if "milk" in i["allergens"]["contains"])
    body = ok(client.get(f"{API}/recipes/{rid}", params={"exclude_allergens": ["milk"]}))
    assert body["recipe"]["suitability"]["status"] == "hidden"
    assert body["recipe"]["suitability"]["reasons"][0]["restriction_ids"] == ["milk"]


def test_recipe_not_found(client):
    assert client.get(f"{API}/recipes/999999").status_code == 404


# --- покупки -----------------------------------------------------------------------------------

def purchase_body(rub):
    return {"servings": 2, "request_id": "00000000-0000-4000-8000-000000000002",
            "filters": {"q": "", "mode": "all", "max_minutes": None, "max_kcal_per_serving": None,
                        "equipment": ["stove", "oven", "microwave", "no_cook"], "exclude_allergens": []},
            "budget": {"minor_units": rub * 100, "currency": "RUB"}}


def test_single_purchase(client):
    body = ok(client.post(f"{API}/recommendations/single-purchase", json=purchase_body(500)))
    assert_contract(body, "SinglePurchaseResult")
    assert body["status"] == "found" and body["options"][0]["unlocked_recipe_ids"]
    assert all(o["shopping_item"]["total_price"]["minor_units"] <= 50000 for o in body["options"])
    empty = ok(client.post(f"{API}/recommendations/single-purchase", json=purchase_body(0)))
    assert empty["status"] == "no_plan" and empty["options"] == []


def test_budget_plan(client):
    body = ok(client.post(f"{API}/recommendations/budget", json=purchase_body(500)))
    assert_contract(body, "PurchaseResult")
    assert body["status"] == "found" and body["total_cost"]["minor_units"] <= 50000 and body["unlocked_recipe_ids"]


# --- распознавание ----------------------------------------------------------------------------

def test_recognition_and_import(receipt_client, codes):
    c = receipt_client
    rec = ok(c.post(f"{API}/recognitions", data={"kind": "receipt"}, files={"file": ("check.jpg", JPEG, "image/jpeg")}), 202)
    assert_contract(rec, "Recognition")
    assert rec["status"] == "succeeded" and [l["status"] for l in rec["items"]] == ["matched", "matched"]
    assert_contract(ok(c.get(f"{API}/recognitions/{rec['id']}")), "Recognition")

    items = [{"line_id": l["line_id"], "ingredient_id": l["candidates"][0]["ingredient_id"],
              "quantity": l["suggested_quantity"]} for l in rec["items"]]
    imported = ok(c.post(f"{API}/recognition-imports", json={"recognition_id": rec["id"], "kind": "receipt", "items": items}))
    assert_contract(imported, "ImportResult")
    pantry = {i["ingredient_id"]: i["quantity"] for i in imported["pantry"]}
    assert pantry[codes["Молоко"]] is None  # в демо-кладовке молоко «есть без количества» — остаётся без количества
    assert pantry[codes["Яйцо куриное"]] is None
    again = c.post(f"{API}/recognition-imports", json={"recognition_id": rec["id"], "kind": "receipt", "items": items})
    assert again.status_code == 409 and again.json()["error"]["code"] == "already_imported"


def test_recognition_rejects_non_image(receipt_client):
    r = receipt_client.post(f"{API}/recognitions", data={"kind": "receipt"}, files={"file": ("a.gif", b"GIF89a....", "image/gif")})
    assert r.status_code == 415 and r.json()["error"]["code"] == "unsupported_media_type"


def test_recognition_not_configured(client, monkeypatch):
    monkeypatch.delenv("GIGACHAT_MODEL", raising=False)
    r = client.post(f"{API}/recognitions", data={"kind": "receipt"}, files={"file": ("c.jpg", JPEG, "image/jpeg")})
    assert r.status_code == 503 and r.json()["error"]["code"] == "service_unavailable"


def test_ml_and_grams_interchangeable(codes):
    c = make_client(demo_pantry=False)
    milk = codes["Молоко"]
    body = ok(c.post(f"{API}/me/pantry/add", json={"ingredient_id": milk, "quantity": {"value": 1000, "unit": "ml"}}))
    q = body["items"][0]["quantity"]
    assert q["value"] == 1000 and q["unit"] in ("g", "ml")


def test_import_from_empty_pantry(codes):
    import json

    from dishgraph.recognition import FakeProvider

    milk = codes["Молоко"]
    answer = json.dumps({"items": [{"raw_name": "МОЛОКО 1Л", "candidates": [{"code": milk, "confidence": 0.95}],
                                    "quantity": {"value": 1, "unit": "l"}}]})
    c = make_client(provider_factory=lambda: FakeProvider(answer), demo_pantry=False)
    rec = ok(c.post(f"{API}/recognitions", data={"kind": "receipt"}, files={"file": ("c.jpg", JPEG, "image/jpeg")}), 202)
    line = rec["items"][0]
    out = ok(c.post(f"{API}/recognition-imports", json={"recognition_id": rec["id"], "kind": "receipt", "items": [
        {"line_id": line["line_id"], "ingredient_id": milk, "quantity": line["suggested_quantity"]}]}))
    # 1 л из чека → 1000 мл → у молока в каталоге только граммы → 1000 г
    assert out["pantry"] == [{"ingredient_id": milk, "name": "Молоко", "quantity": {"value": 1000, "unit": "g"}}]


def test_android_catalog(client):
    body = ok(client.get(f"{API}/catalog/android"))
    assert len(body["recipes"]) == 406 and len(body["ingredients"]) == 851 and len(body["demo_pantry"]) == 19
    ids = {i["id"] for i in body["ingredients"]}
    staples = {c for c, i in client.app.state.catalog.ingredients.items() if i.is_staple}
    for r in body["recipes"]:  # ограничения Recipe в приложении
        assert 1 <= r["servings"] <= 12 and r["minutes"] > 0 and r["ingredients"]
        assert all(i["quantity"]["value"] > 0 and i["ingredient_id"] in ids for i in r["ingredients"])
        assert not staples & {i["ingredient_id"] for i in r["ingredients"]}
        assert set(r["allergens"]) <= {"MILK", "EGGS", "GLUTEN", "NUTS", "FISH", "SOY"}
        assert set(r["methods"]) <= {"STOVE", "OVEN", "MICROWAVE", "NO_COOK"}
