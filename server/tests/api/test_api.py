from ..support.http import FILTERS, auth, check, mutation, png, session
import copy
from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

from fastapi.testclient import TestClient

from ..support.application import create_app


def test_all_contract_operations_have_routes_and_runtime_docs(app, client):
    expected = {(method.upper(), "/api/v1" + path)
                for path, methods in app.state.contract.spec["paths"].items() for method in methods}
    def registered_routes(routes):
        for route in routes:
            if hasattr(route, "original_router"):
                yield from registered_routes(route.original_router.routes)
            else:
                yield route

    actual = {(method, route.path) for route in registered_routes(app.routes)
              for method in getattr(route, "methods", [])}
    assert expected <= actual
    assert client.get("/api/v1/health").json() == {"status": "ok", "api_version": "v1"}
    assert client.get("/docs").status_code == 200
    assert client.get("/openapi.json").json()["servers"] == [{"url": "/api/v1"}]


def test_auth_required_and_provider_not_faked():
    app = create_app(auth_providers={})
    with TestClient(app) as client:
        check(app, client.get("/api/v1/me"), "Error", 401)
        payload = {"oauth_token": "synthetic-token"}
        check(app, client.post("/api/v1/auth/yandex", json=payload), "Error", 503)
        assert client.get("/api/v1/me", headers={"Authorization": "Bearer fabricated"}).status_code == 401


def test_yandex_identity_is_stable_and_users_are_isolated():
    class Provider:
        def exchange(self, payload):
            return payload["oauth_token"]

    app = create_app(auth_providers={"yandex": Provider()})
    with TestClient(app) as client:
        first = check(app, client.post("/api/v1/auth/yandex", json={"oauth_token": "first-user"}), "Session")
        repeated = check(app, client.post("/api/v1/auth/yandex", json={"oauth_token": "first-user"}), "Session")
        other = check(app, client.post("/api/v1/auth/yandex", json={"oauth_token": "other-user"}), "Session")
        assert first["user_id"] == repeated["user_id"]
        assert first["user_id"] != other["user_id"]
        assert "no-store" in client.post("/api/v1/auth/yandex", json={"oauth_token": "synthetic-token"}).headers["cache-control"]


def test_vk_login_is_not_available(app, client):
    assert "/auth/vk" not in app.state.contract.spec["paths"]
    assert "VkExchange" not in app.state.contract.spec["components"]["schemas"]
    check(app, client.post("/api/v1/auth/vk", json={}), "Error", 404)


def test_pantry_add_set_zero_delete_unknown_and_replay(app, client):
    headers = auth(app)
    request = {"ingredient_id": "rice", "quantity": {"value": 500, "unit": "g"}}
    old = mutation(client, headers)
    initial = client.post("/api/v1/me/pantry/add", json=request, headers=old)
    check(app, initial, "Pantry")
    replay = client.post("/api/v1/me/pantry/add", json=request, headers=old)
    assert replay.json() == initial.json()
    assert replay.headers["etag"] == initial.headers["etag"]
    changed = {**request, "quantity": {"value": 200, "unit": "g"}}
    check(app, client.post("/api/v1/me/pantry/add", json=changed, headers=old), "Error", 409)
    result = check(app, client.post("/api/v1/me/pantry/add", json=changed, headers=mutation(client, headers)), "Pantry")
    assert result["items"][0]["quantity"]["value"] == 700
    assert client.put("/api/v1/me/pantry/rice", json={"quantity": None}, headers=mutation(client, headers)).json()["items"][0]["quantity"] is None
    assert client.post("/api/v1/me/pantry/add", json=changed, headers=mutation(client, headers)).json()["items"][0]["quantity"] is None
    assert client.put("/api/v1/me/pantry/rice", json={"quantity": {"value": 0, "unit": "g"}}, headers=mutation(client, headers)).json()["items"] == []


def test_preconditions_and_validation_do_not_change_state(app, client):
    headers = auth(app)
    before = client.get("/api/v1/me/state", headers=headers).json()
    body = {"ingredient_id": "rice", "quantity": {"value": 1, "unit": "g"}}
    check(app, client.post("/api/v1/me/pantry/add", json=body, headers={**headers, "Idempotency-Key": str(uuid4())}), "Error", 428)
    check(app, client.post("/api/v1/me/pantry/add", json=body, headers={**headers, "If-Match": '"state-99"', "Idempotency-Key": str(uuid4())}), "Error", 412)
    for value in (0, -1, 1_000_001):
        bad = {**body, "quantity": {"value": value, "unit": "g"}}
        check(app, client.post("/api/v1/me/pantry/add", json=bad, headers=mutation(client, headers)), "Error", 422)
    assert client.get("/api/v1/me/state", headers=headers).json() == before


def test_atomic_purchased_batch_rolls_back_and_replays(app, client):
    headers = auth(app)
    invalid = {"items": [{"ingredient_id": "rice", "quantity": {"value": 500, "unit": "g"}},
                         {"ingredient_id": "tomato", "quantity": {"value": 2, "unit": "pcs"}}]}
    before = client.get("/api/v1/me/state", headers=headers).json()
    check(app, client.post("/api/v1/me/pantry/purchased", json=invalid, headers=mutation(client, headers)), "Error", 409)
    assert client.get("/api/v1/me/pantry", headers=headers).json()["items"] == []
    assert client.get("/api/v1/me/state", headers=headers).json() == before
    valid = copy.deepcopy(invalid)
    valid["items"][1]["quantity"] = {"value": 1000, "unit": "g"}
    old = mutation(client, headers)
    initial = client.post("/api/v1/me/pantry/purchased", json=valid, headers=old)
    result = check(app, initial, "Pantry")
    assert result["state_version"] == 1
    assert client.post("/api/v1/me/pantry/purchased", json=valid, headers=old).json() == result
    assert len(client.get("/api/v1/me/pantry", headers=headers).json()["items"]) == 2


def test_concurrent_writes_detect_version_conflict(app, client):
    headers = mutation(client, auth(app))
    body = {"ingredient_id": "rice", "quantity": {"value": 100, "unit": "g"}}

    def add(_):
        return client.post("/api/v1/me/pantry/add", json=body,
                           headers={**headers, "Idempotency-Key": str(uuid4())}).status_code

    with ThreadPoolExecutor(max_workers=2) as executor:
        assert sorted(executor.map(add, range(2))) == [200, 412]


def test_stub_resets_between_instances_and_users_are_isolated(tmp_path):
    app = create_app()
    headers = auth(app, "alice")
    with TestClient(app) as client:
        client.post("/api/v1/me/pantry/add", json={"ingredient_id": "rice", "quantity": None}, headers=mutation(client, headers))
        other = auth(app, "bob")
        assert client.get("/api/v1/me/pantry", headers=other).json()["items"] == []
    reopened = create_app()
    with TestClient(reopened) as client:
        assert client.get("/api/v1/me/pantry", headers=headers).status_code == 401
        assert client.get("/api/v1/me/pantry", headers=auth(reopened, "alice")).json()["items"] == []
    assert not list(tmp_path.iterdir())


def test_refresh_rotation_reuse_revokes_family(app, client):
    original = session(app)
    rotated = check(app, client.post("/api/v1/auth/refresh", json={"refresh_token": original["refresh_token"]}), "Session")
    active = {"Authorization": "Bearer " + rotated["access_token"]}
    assert client.get("/api/v1/me", headers=active).status_code == 200
    check(app, client.post("/api/v1/auth/refresh", json={"refresh_token": original["refresh_token"]}), "Error", 401)
    assert client.get("/api/v1/me", headers=active).status_code == 401


def test_logout_revokes_current_session(app, client):
    headers = auth(app)
    response = client.post("/api/v1/auth/logout", headers=headers)
    assert response.status_code == 204 and response.content == b""
    assert client.get("/api/v1/me", headers=headers).status_code == 401


def test_search_synonyms_cursor_and_favorites(app, client):
    headers = auth(app)
    result = check(app, client.get("/api/v1/ingredients?q=помидор", headers=headers), "IngredientPage")
    assert result["items"][0]["id"] == "tomato"
    for i in ("rice", "tomato"):
        check(app, client.put("/api/v1/me/favorites/ingredients/" + i, headers=mutation(client, headers)), "MutationResult")
    page = check(app, client.get("/api/v1/me/favorites/ingredients?limit=1", headers=headers), "IngredientPage")
    cursor = page["page"]["next_cursor"]
    assert cursor
    second = client.get("/api/v1/me/favorites/ingredients", params={"limit": 1, "cursor": cursor}, headers=headers)
    assert second.json()["items"][0]["id"] != page["items"][0]["id"]
    client.delete("/api/v1/me/favorites/ingredients/rice", headers=mutation(client, headers))
    check(app, client.get("/api/v1/me/favorites/ingredients", params={"limit": 1, "cursor": cursor}, headers=headers), "Error", 409)


def test_unweighed_stock_and_scaled_portions_use_engine(app, client):
    headers = auth(app)
    client.post("/api/v1/me/pantry/add", json={"ingredient_id": "rice", "quantity": None}, headers=mutation(client, headers))
    unscaled = check(app, client.get("/api/v1/recipes/rice_tomato?servings=4", headers=headers), "RecipeDetail")
    assert unscaled["recipe"]["servings"] == 4
    assert unscaled["recipe"]["availability"]["status"] == "missing"
    assert unscaled["ingredients"][0]["required"] == {"value": 400, "unit": "g"}
    assert unscaled["recipe"]["buy_cost"] is not None
    detail = check(app, client.get("/api/v1/recipes/rice_tomato?servings=2", headers=headers), "RecipeDetail")
    assert detail["recipe"]["availability"]["unknown_quantity_ids"] == ["rice"]
    assert detail["ingredients"][0]["availability"] == "enough"
    assert detail["ingredients"][0]["required"] == {"value": 200, "unit": "g"}


def test_snapshot_pages_graph_and_invalidation(app, client):
    headers = auth(app)
    request = {"request_id": str(uuid4()), "servings": 2, "filters": FILTERS, "visibility": "visible", "limit": 1}
    first = check(app, client.post("/api/v1/recommendations", json=request, headers=headers), "RecommendationPage", 201)
    assert first["visible_total"] == 2 and first["page"]["has_more"]
    path = "/api/v1/recommendations/" + first["snapshot_id"]
    full_graph = check(app, client.get(path + "/graph", headers=headers), "RecommendationGraph")
    node_ids = {n["id"] for n in full_graph["graph"]["nodes"]}
    assert all(e["source"] in node_ids and e["target"] in node_ids for e in full_graph["graph"]["edges"])
    assert len([n for n in full_graph["graph"]["nodes"] if n["kind"] == "recipe"]) == 2
    assert full_graph["servings"] == first["servings"] == 2
    second = check(app, client.get(path, params={"cursor": first["page"]["next_cursor"]}, headers=headers), "RecommendationPage")
    assert second["items"][0]["id"] != first["items"][0]["id"]
    assert client.get(path + "/graph", headers=headers).json() == full_graph
    assert client.get(path, headers=auth(app, "bob")).status_code == 404
    client.post("/api/v1/me/pantry/add", json={"ingredient_id": "rice", "quantity": None}, headers=mutation(client, headers))
    assert client.get(path, headers=headers).status_code == 409
    assert client.get(path + "/graph", headers=headers).status_code == 409


def test_profile_is_saved_but_unsupported_medical_calculation_is_rejected(app, client):
    headers = auth(app)
    profile = client.get("/api/v1/me", headers=headers).json()
    prefs = {**profile["preferences"], "diabetes": True}
    changed = check(app, client.patch("/api/v1/me", json={"preferences": prefs}, headers=mutation(client, headers)), "Profile")
    assert changed["unsupported_restrictions"] == ["diabetes"]
    check(app, client.get("/api/v1/recipes/tomato_cheese", headers=headers), "Error", 503)


def test_single_purchases_and_budget_plan_use_engine(app, client):
    headers = auth(app)
    client.post("/api/v1/me/pantry/add", json={"ingredient_id": "tomato", "quantity": {"value": 1000, "unit": "g"}}, headers=mutation(client, headers))
    body = {"request_id": str(uuid4()), "servings": 2, "filters": FILTERS, "budget": {"minor_units": 100000, "currency": "RUB"}}
    single = check(app, client.post("/api/v1/recommendations/single-purchase", json=body, headers=headers), "SinglePurchaseResult")
    assert single["options"][0]["shopping_item"]["total_price"]["minor_units"] == 10000
    before = client.get("/api/v1/me/state", headers=headers).json()
    plan = check(app, client.post("/api/v1/recommendations/budget", json=body, headers=headers), "PurchaseResult")
    assert plan["status"] == "found"
    assert plan["shopping_items"]
    assert plan["unlocked_recipe_ids"]
    assert plan["total_cost"]["minor_units"] <= body["budget"]["minor_units"]
    assert sum(item["total_price"]["minor_units"] for item in plan["shopping_items"]) == plan["total_cost"]["minor_units"]
    assert client.get("/api/v1/me/state", headers=headers).json() == before


class RecognitionFake:
    def __init__(self):
        self.calls = 0

    def recognize(self, image, kind):
        self.calls += 1
        return [{"line_id": "line-1", "raw_name": "Рис", "candidates": [{"ingredient_id": "rice", "name": "Рис", "confidence": 0.9}],
                 "suggested_quantity": None, "status": "matched"}]


def test_recognition_import_confirmation_replay_and_owner(tmp_path):
    recognizer = RecognitionFake()
    app = create_app(recognizer=recognizer)
    with TestClient(app) as client:
        headers = auth(app)
        upload_headers = {**headers, "Idempotency-Key": str(uuid4())}
        uploaded = client.post("/api/v1/recognitions", data={"kind": "products"}, files={"file": ("photo.png", png(), "image/png")}, headers=upload_headers)
        result = check(app, uploaded, "Recognition", 202)
        repeated = client.post("/api/v1/recognitions", data={"kind": "products"}, files={"file": ("photo.png", png(), "image/png")}, headers=upload_headers)
        assert repeated.json() == result and recognizer.calls == 1
        assert client.get("/api/v1/me/pantry", headers=headers).json()["items"] == []
        assert client.get(uploaded.headers["location"], headers=auth(app, "bob")).status_code == 404
        body = {"recognition_id": result["id"], "kind": "products", "items": [{"line_id": "line-1", "ingredient_id": "rice", "quantity": None}]}
        import_headers = mutation(client, headers)
        initial = check(app, client.post("/api/v1/recognition-imports", json=body, headers=import_headers), "ImportResult")
        assert initial["pantry"][0]["quantity"] is None
        assert client.post("/api/v1/recognition-imports", json=body, headers=import_headers).json() == initial
        assert client.post("/api/v1/recognition-imports", json=body, headers=mutation(client, headers)).status_code == 409


def test_receipt_import_allows_unknown_quantity_and_invalid_image_is_rejected(app, client):
    headers = auth(app)
    for kind in ("receipt", "products"):
        response = client.post("/api/v1/recognitions", data={"kind": kind},
                               files={"file": ("fake.png", b"not a PNG", "image/png")},
                               headers={**headers, "Idempotency-Key": str(uuid4())})
        check(app, response, "Error", 415)
    valid = client.post("/api/v1/recognitions", data={"kind": "receipt"},
                        files={"file": ("screenshot.png", png(), "image/png")},
                        headers={**headers, "Idempotency-Key": str(uuid4())})
    check(app, valid, "Error", 503)
    # Неизвестный вес — явный null, как и для products; чужая/неизвестная задача всё ещё 404.
    body = {"recognition_id": "missing", "kind": "receipt",
            "items": [{"line_id": "line-1", "ingredient_id": "rice", "quantity": None}]}
    check(app, client.post("/api/v1/recognition-imports", json=body, headers=mutation(client, headers)),
          "Error", 404)


def test_receipt_import_with_null_quantity_adds_product_without_weight(tmp_path):
    recognizer = RecognitionFake()
    app = create_app(recognizer=recognizer)
    with TestClient(app) as client:
        headers = auth(app)
        uploaded = client.post("/api/v1/recognitions", data={"kind": "receipt"},
                               files={"file": ("receipt.png", png(), "image/png")},
                               headers={**headers, "Idempotency-Key": str(uuid4())})
        result = check(app, uploaded, "Recognition", 202)
        body = {"recognition_id": result["id"], "kind": "receipt",
                "items": [{"line_id": "line-1", "ingredient_id": "rice", "quantity": None}]}
        imported = check(app, client.post("/api/v1/recognition-imports", json=body,
                                          headers=mutation(client, headers)), "ImportResult")
        assert imported["pantry"][0]["ingredient_id"] == "rice"
        assert imported["pantry"][0]["quantity"] is None


def test_without_engine_no_server_search_or_calculation_fallback_is_used(app, client):
    app.state.service.catalog.gateway.engine = None
    headers = auth(app)
    check(app, client.get("/api/v1/ingredients?q=рис", headers=headers), "Error", 503)
    check(app, client.get("/api/v1/recipes/rice_tomato", headers=headers), "Error", 503)
