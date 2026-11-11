"""Integration tests require a dedicated seeded database named *_test.

Set ALMOSTDONE_TEST_DATABASE_URL to a migrated database; no migrations are applied by tests, and isolated test
accounts are created. No catalogue rows or pre-existing accounts are removed.
"""
import os
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urlsplit
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from almostdone_server.main import create_app
from almostdone_server.repositories.postgres import PostgresStore
from almostdone_server.errors import StorageUnavailable
from ..support.http import check, mutation, png, FILTERS

DSN = os.environ.get("ALMOSTDONE_TEST_DATABASE_URL")
pytestmark = pytest.mark.skipif(not DSN, reason="Dedicated PostgreSQL integration database is not configured")


@pytest.fixture(scope="module")
def database():
    assert urlsplit(DSN).path.endswith("_test"), "Only a dedicated *_test database may be used"
    return DSN


class Provider:
    def exchange(self, payload):
        return payload["oauth_token"]


def application(dsn, **kwargs):
    return create_app(store=PostgresStore(dsn), auth_providers={"yandex": Provider()}, **kwargs)


def login(client, subject=None):
    response = client.post("/api/v1/auth/yandex", json={"oauth_token": subject or "test-" + uuid4().hex})
    assert response.status_code == 200, response.text
    session = response.json()
    return {"Authorization": "Bearer " + session["access_token"]}, session


def test_catalog_exports_ingredient_nutrition_from_postgres(database):
    app = application(database)
    with app.state.service.store.transaction() as db:
        rows = list(db.execute('SELECT code, kcal, protein, fat, carbs FROM ingredients'))
    expected = {row['code']: {'kcal': float(row['kcal']), 'protein_g': float(row['protein']),
                             'fat_g': float(row['fat']), 'carbs_g': float(row['carbs'])} for row in rows}
    with TestClient(app) as client:
        headers, _ = login(client)
        response = client.get('/api/v1/catalog', headers=headers)
        assert response.status_code == 200, response.text
        actual = {item['id']: item['nutrition_per_100g'] for item in response.json()['ingredients']}
        assert actual == expected


def test_readiness_checks_real_postgres_schema_and_migrations(database):
    with TestClient(application(database)) as client:
        response = client.get('/api/v1/health/ready')
        assert response.status_code == 200, response.text
        assert response.json()['checks']['storage'] == 'ok'


def test_domain_data_session_and_version_survive_restart(database):
    app = application(database)
    assert len(app.state.service.catalog.recipes) >= 100
    code = next(iter(app.state.service.catalog.ingredients))
    with TestClient(app) as client:
        subject = "restart-" + uuid4().hex
        headers, session = login(client, subject)
        command = {"ingredient_id": code, "quantity": {"value": 999999.99, "unit": "g"}}
        command_headers = mutation(client, headers)
        first = client.post("/api/v1/me/pantry/add", json=command, headers=command_headers)
        check(app, first, "Pantry")
        assert first.headers["x-storage-mode"] == "postgresql"
        recipe_id = next(iter(app.state.service.catalog.recipes))
        assert client.put("/api/v1/me/favorites/recipes/" + recipe_id, headers=mutation(client, headers)).status_code == 200
        version = client.get('/api/v1/me/state', headers=headers).json()['state_version']
    reopened = application(database)
    with TestClient(reopened) as client:
        assert client.get("/api/v1/me", headers=headers).status_code == 200
        assert client.get('/api/v1/me/state', headers=headers).json()['state_version'] == version
        assert client.post('/api/v1/me/pantry/add', json=command, headers=command_headers).json() == first.json()
        headers, same_identity = login(client, subject)
        assert same_identity["user_id"] == session["user_id"]
        assert client.get("/api/v1/me/pantry", headers=headers).json()["items"][0]["quantity"]["value"] == 999999.99
        # Persistence does not depend on whether the engine can calculate this recipe.
        store = reopened.state.service.store
        with store.transaction() as db:
            restored = store.user(db, same_identity["user_id"])
            assert restored["favorites"]["recipes"] == [recipe_id]
        _, same_identity = login(client, subject)
        assert same_identity["user_id"] == session["user_id"]
        other, _ = login(client)
        assert client.get("/api/v1/me/pantry", headers=other).json()["items"] == []


def test_shared_store_serializes_writes_by_user_version(database):
    first = application(database)
    second = application(database)
    code = next(iter(first.state.service.catalog.ingredients))
    with TestClient(first) as left, TestClient(second) as right:
        headers, _ = login(left)
        version = left.get("/api/v1/me/state", headers=headers).headers["etag"]

        def add(client):
            return client.post("/api/v1/me/pantry/add", json={"ingredient_id": code, "quantity": {"value": 100, "unit": "g"}},
                headers={**headers, "If-Match": version, "Idempotency-Key": str(uuid4())}).status_code

        with ThreadPoolExecutor(max_workers=2) as pool:
            assert sorted(pool.map(add, (left, right))) == [200, 412]
        assert right.get("/api/v1/me/pantry", headers=headers).json()["items"][0]["quantity"]["value"] == 100


def test_refresh_reuse_revokes_sessions_in_shared_store(database):
    app = application(database)
    reopened = application(database)
    with TestClient(app) as first, TestClient(reopened) as second:
        _, original = login(first)
        rotated = first.post("/api/v1/auth/refresh", json={"refresh_token": original["refresh_token"]}).json()
        active = {"Authorization": "Bearer " + rotated["access_token"]}
        assert second.get("/api/v1/me", headers=active).status_code == 200
        assert second.post("/api/v1/auth/refresh", json={"refresh_token": original["refresh_token"]}).status_code == 401
        assert first.get("/api/v1/me", headers=active).status_code == 401


def test_confirmed_import_and_recognition_survive_restart(database):
    app = application(database)
    code = next(iter(app.state.service.catalog.ingredients))

    class Recognizer:
        def recognize(self, image, kind):
            return [{"line_id": "line-1", "raw_name": "Test", "candidates": [{"ingredient_id": code, "name": "Test", "confidence": 1}],
                     "suggested_quantity": None, "status": "matched"}]

    app.state.service.recognizer = Recognizer()
    with TestClient(app) as client:
        headers, _ = login(client)
        uploaded = client.post("/api/v1/recognitions", data={"kind": "products"}, files={"file": ("image.png", png(), "image/png")},
                               headers={**headers, "Idempotency-Key": str(uuid4())})
        assert uploaded.status_code == 202, uploaded.text
        rid = uploaded.json()["id"]
        body = {"recognition_id": rid, "kind": "products", "items": [{"line_id": "line-1", "ingredient_id": code, "quantity": None}]}
        command_headers = mutation(client, headers)
        first = client.post("/api/v1/recognition-imports", json=body, headers=command_headers)
        assert first.status_code == 200, first.text
    with TestClient(application(database)) as client:
        assert client.get('/api/v1/recognitions/' + rid, headers=headers).status_code == 200
        assert client.post("/api/v1/recognition-imports", json=body, headers=command_headers).json() == first.json()
        assert client.post("/api/v1/recognition-imports", json=body, headers=mutation(client, headers)).status_code == 409
        assert client.get("/api/v1/me/pantry", headers=headers).json()["items"][0]["quantity"] is None


def test_database_rollback_preserves_previous_state_and_idempotency_key(database):
    app = application(database)
    codes = list(app.state.service.catalog.ingredients)[:2]
    with TestClient(app) as client:
        headers, _ = login(client)
        command_headers = mutation(client, headers)
        body = {"items": [{"ingredient_id": codes[0], "quantity": {"value": 100, "unit": "g"}},
                          {"ingredient_id": "does_not_exist", "quantity": {"value": 100, "unit": "g"}}]}
        assert client.post("/api/v1/me/pantry/purchased", json=body, headers=command_headers).status_code == 422
        assert client.get("/api/v1/me/pantry", headers=headers).json()["items"] == []
        body["items"][1]["ingredient_id"] = codes[1]
        assert client.post("/api/v1/me/pantry/purchased", json=body, headers=command_headers).status_code == 200
        store = app.state.service.store
        user_id = int(client.get('/api/v1/me', headers=headers).json()['user_id'])
        with store.transaction() as db:
            assert db.execute("SELECT count(*) AS n FROM user_pantry WHERE user_id=%s", (user_id,)).fetchone()['n'] == 2


def test_expired_refresh_keeps_valid_access_until_its_own_expiry(database, monkeypatch):
    app = application(database)
    with TestClient(app) as client:
        headers, session = login(client)
        import time
        now = time.time()
        with app.state.service.store.transaction() as db:
            session = app.state.service.auth.issue(db, session['user_id'], refresh_until=now + 1)
        headers = {'Authorization': 'Bearer ' + session['access_token']}
        monkeypatch.setattr('almostdone_server.services.auth.time.time', lambda: now + 2)
        app.state.service.purge()
        assert client.get("/api/v1/me", headers=headers).status_code == 200
        assert client.post("/api/v1/auth/refresh", json={"refresh_token": session["refresh_token"]}).status_code == 401


def test_decimal_pantry_addition_does_not_fail_database_precision_check(database):
    app = application(database)
    code = next(iter(app.state.service.catalog.ingredients))
    with TestClient(app) as client:
        headers, _ = login(client)
        for value in (0.1, 0.2):
            response = client.post("/api/v1/me/pantry/add", headers=mutation(client, headers),
                                   json={"ingredient_id": code, "quantity": {"value": value, "unit": "g"}})
            assert response.status_code == 200, response.text
        item = client.get("/api/v1/me/pantry", headers=headers).json()["items"][0]
        assert item["quantity"] == {"value": 0.3, "unit": "g"}


def test_preferences_are_saved_in_existing_relations_and_loaded_after_restart(database):
    app = application(database)
    subject = "preferences-" + uuid4().hex
    with TestClient(app) as client:
        headers, session = login(client, subject)
        store = app.state.service.store
        with store.transaction() as db:
            state = app.state.service.states.load(db, session["user_id"])
            state["preferences"].update(food_type="vegetarian", gluten_free=True,
                                        excluded_allergens=["milk"], diet_table_id="pevzner_15")
            app.state.service.states.save(db, session["user_id"], state)
    with TestClient(application(database)) as client:
        headers, _ = login(client, subject)
        preferences = client.get("/api/v1/me", headers=headers).json()["preferences"]
        assert preferences["food_type"] == "vegetarian"
        assert preferences["gluten_free"] is True
        assert preferences["excluded_allergens"] == ["milk"]
        assert preferences["diet_table_id"] == "pevzner_15"


def test_statement_timeout_is_reported_as_temporary_storage_failure(database):
    store = PostgresStore(database)
    with pytest.raises(StorageUnavailable):
        with store.transaction() as db:
            db.execute("SET LOCAL statement_timeout = '1ms'")
            db.execute("SELECT pg_sleep(0.05)")


def test_seed_catalog_partial_recipes_do_not_block_recommendations(database):
    app = application(database)
    catalog = app.state.service.catalog
    assert any(item.get("qty_g") is None and item.get("is_optional")
               for raw in catalog.recipes.values() for item in raw["items"]), "Exercise nullable optional quantities in the actual seed catalogue"
    with TestClient(app) as client:
        headers, _ = login(client)
        body = {"request_id": str(uuid4()), "servings": 2, "filters": FILTERS, "visibility": "visible", "limit": 100}
        first = check(app, client.post("/api/v1/recommendations", json=body, headers=headers), "RecommendationPage", 201)
        assert first["visible_total"] == len(catalog.recipes)
        ids = [card["id"] for card in first["items"]]
        page = first
        while page["page"]["has_more"]:
            page = check(app, client.get("/api/v1/recommendations/" + first["snapshot_id"],
                                        params={"cursor": page["page"]["next_cursor"]}, headers=headers), "RecommendationPage")
            ids.extend(card["id"] for card in page["items"])
        assert len(ids) == len(set(ids)) == len(catalog.recipes)
        assert set(ids) == set(catalog.recipes)
        partial_id = next(rid for rid, raw in catalog.recipes.items() if raw["servings"] != 2)
        detail = check(app, client.get("/api/v1/recipes/" + partial_id, headers=headers), "RecipeDetail")
        assert detail["recipe"]["availability"]["status"] == "unknown"
        assert detail["recipe"]["buy_cost"] is None
