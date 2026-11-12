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


def test_seed_catalog_mixed_portions_do_not_block_recommendations(database):
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
        scaled_id = next(rid for rid, raw in catalog.recipes.items() if raw["servings"] != 2)
        detail = check(app, client.get("/api/v1/recipes/" + scaled_id, headers=headers), "RecipeDetail")
        assert detail["recipe"]["servings"] == 2
        assert detail["recipe"]["nutrition_per_serving"] is not None
        assert detail["recipe"]["buy_cost"] is not None
        required = next(item for item in detail['ingredients'] if not item['optional'])
        raw = next(item for item in catalog.recipes[scaled_id]['items'] if item['code'] == required['ingredient_id'])
        assert required['required'] == catalog.quantity(required['ingredient_id'], raw['qty_g'] * 2 / catalog.recipes[scaled_id]['servings'])

@pytest.mark.parametrize('preferences', [
    {'food_type': 'vegetarian'}, {'food_type': 'vegan'}, {'gluten_free': True},
    {'lactose_free': True}, {'diet_table_id': 'pevzner_1'},
])
def test_dietary_api_matches_existing_sql_visibility(database, preferences):
    app = application(database)
    with TestClient(app) as client:
        headers, session = login(client)
        prefs = client.get('/api/v1/me', headers=headers).json()['preferences']
        response = client.patch('/api/v1/me', headers=mutation(client, headers),
                                json={'preferences': {**prefs, **preferences}})
        assert response.status_code == 200, response.text
        assert response.json()['unsupported_restrictions'] == []
        with app.state.service.store.transaction() as db:
            rows = list(db.execute('SELECT recipe_id,is_hidden,skip_optional FROM user_recipe_visibility WHERE user_id=%s',
                                   (int(session['user_id']),)))
        expected_hidden = {str(row['recipe_id']) for row in rows if row['is_hidden']}
        assert expected_hidden
        request = {'request_id': str(uuid4()), 'servings': 2, 'filters': FILTERS,
                   'visibility': 'hidden', 'limit': 100}
        response = client.post('/api/v1/recommendations', json=request, headers=headers)
        assert response.status_code == 201, response.text
        page = response.json()
        actual = {item['id'] for item in page['items']}
        while page['page']['has_more']:
            response = client.get('/api/v1/recommendations/' + page['snapshot_id'],
                                  params={'cursor': page['page']['next_cursor']}, headers=headers)
            assert response.status_code == 200, response.text
            page = response.json()
            actual.update(item['id'] for item in page['items'])
        assert actual == expected_hidden
        recipe_id = sorted(expected_hidden)[0]
        response = client.get('/api/v1/recipes/' + recipe_id, headers=headers)
        assert response.status_code == 200, response.text
        assert response.json()['recipe']['suitability']['status'] == 'hidden'
        reason = next(r for r in response.json()['recipe']['suitability']['reasons'] if r['code'] == 'excluded_diet')
        assert reason['restriction_ids']
        assert all(not name.startswith('Стол ') for name in reason['restriction_ids'])
        favorite = client.put('/api/v1/me/favorites/recipes/' + recipe_id, headers=mutation(client, headers))
        assert favorite.status_code == 200, favorite.text
        response = client.get('/api/v1/me/favorites/recipes', headers=headers)
        assert response.status_code == 200, response.text
        assert response.json()['items'][0]['suitability']['status'] == 'hidden'
        request['visibility'] = 'visible'
        response = client.post('/api/v1/recommendations', json=request, headers=headers)
        assert response.status_code == 201, response.text
        assert not ({item['id'] for item in response.json()['items']} & expected_hidden)
        purchase = {key: request[key] for key in ('request_id', 'servings', 'filters')}
        purchase['budget'] = {'minor_units': 100000, 'currency': 'RUB'}
        response = client.post('/api/v1/recommendations/budget', json=purchase, headers=headers)
        assert response.status_code == 200, response.text
        assert not (set(response.json()['unlocked_recipe_ids']) & expected_hidden)


def test_optional_dietary_exclusions_are_warnings_from_sql(database):
    app = application(database)
    store = app.state.service.store
    recipe_id = None
    try:
        with store.transaction() as db:
            required = db.execute("SELECT id FROM ingredients WHERE lower(name)='рис'").fetchone()['id']
            optional = db.execute("""
                SELECT i.id, i.code FROM ingredients i
                JOIN ingredient_categories c ON c.ingredient_id=i.id
                JOIN diet_excluded_categories x ON x.category_id=c.category_id
                JOIN diets d ON d.id=x.diet_id
                WHERE d.name='Веганство' AND i.id<>%s LIMIT 1
            """, (required,)).fetchone()
            assert optional is not None
            recipe_id = db.execute("INSERT INTO recipes(title,servings,cook_time_min) VALUES (%s,2,1) RETURNING id",
                                   ('Optional dietary test ' + uuid4().hex,)).fetchone()['id']
            db.execute('INSERT INTO recipe_ingredients(recipe_id,ingredient_id,qty_g,is_optional) VALUES (%s,%s,100,false),(%s,%s,10,true)',
                       (recipe_id, required, recipe_id, optional['id']))
        app = application(database)
        with TestClient(app) as client:
            headers, session = login(client)
            prefs = client.get('/api/v1/me', headers=headers).json()['preferences']
            response = client.patch('/api/v1/me', headers=mutation(client, headers),
                                    json={'preferences': {**prefs, 'food_type': 'vegan'}})
            assert response.status_code == 200, response.text
            with store.transaction() as db:
                row = db.execute('SELECT is_hidden,skip_optional FROM user_recipe_visibility WHERE user_id=%s AND recipe_id=%s',
                                 (int(session['user_id']), recipe_id)).fetchone()
                assert not row['is_hidden'] and row['skip_optional']
            response = client.get('/api/v1/recipes/' + str(recipe_id), headers=headers)
            assert response.status_code == 200, response.text
            assessment = response.json()['recipe']['suitability']
            assert assessment['status'] != 'hidden'
            codes = {code for reason in assessment['reasons'] if reason['code'] == 'skip_optional' for code in reason['ingredient_ids']}
            assert codes == {optional['code']}
    finally:
        if recipe_id is not None:
            with store.transaction() as db:
                db.execute('DELETE FROM recipes WHERE id=%s', (recipe_id,))


def test_dietary_support_and_diabetes_remain_explicit(database):
    app = application(database)
    with TestClient(app) as client:
        headers, _ = login(client)
        options = client.get('/api/v1/dietary-options', headers=headers)
        assert options.status_code == 200, options.text
        support = {item['id']: item['support'] for item in options.json()['items']}
        assert support['vegetarian'] == support['vegan'] == 'supported'
        assert support['gluten_free'] == support['lactose_free'] == 'supported'
        assert support['diabetes'] == 'unsupported'
        assert support['pevzner_15'] == 'supported'
        assert support['pevzner_11'] == 'unsupported'
        prefs = client.get('/api/v1/me', headers=headers).json()['preferences']
        response = client.patch('/api/v1/me', headers=mutation(client, headers),
                                json={'preferences': {**prefs, 'diabetes': True}})
        assert response.status_code == 200
        assert response.json()['unsupported_restrictions'] == ['diabetes']
        recipe_id = next(iter(app.state.service.catalog.recipes))
        response = client.get('/api/v1/recipes/' + recipe_id, headers=headers)
        assert response.status_code == 503
        assert response.json()['error']['details'][0]['field'] == 'dietary_restrictions'


def test_ml_quantities_are_converted_to_mass_and_preserved_after_restart(database):
    # Sesame oil has a non-integer density (0.923 g/ml), exercising DB rounding.
    code = "ing_dd786d8ed9d32aff"
    app = application(database)
    with TestClient(app) as client:
        headers, session = login(client)
        result = check(app, client.post("/api/v1/me/pantry/add", json={"ingredient_id": code,
                       "quantity": {"value": 1, "unit": "ml"}}, headers=mutation(client, headers)), "Pantry")
        assert next(item for item in result["items"] if item["ingredient_id"] == code)["quantity"] == {"value": 1, "unit": "ml"}
        version = result["state_version"]
    with app.state.service.store.transaction() as db:
        grams = db.execute("SELECT qty_g FROM user_pantry p JOIN ingredients i ON i.id=p.ingredient_id WHERE p.user_id=%s AND i.code=%s",
                           (int(session["user_id"]), code)).fetchone()["qty_g"]
        assert str(grams) == "0.92"
    reopened = application(database)
    with TestClient(reopened) as client:
        result = check(reopened, client.get("/api/v1/me/pantry", headers=headers), "Pantry")
        assert next(item for item in result["items"] if item["ingredient_id"] == code)["quantity"] == {"value": 1, "unit": "ml"}
        assert result["state_version"] == version
        recipe_id = next(rid for rid, recipe in reopened.state.service.catalog.recipes.items()
                         if any(item["code"] == code for item in recipe["items"]))
        check(reopened, client.get("/api/v1/recipes/" + recipe_id, headers=headers), "RecipeDetail")
