import time
import asyncio
from contextlib import asynccontextmanager, aclosing
from threading import Event
from uuid import uuid4
from concurrent.futures import ThreadPoolExecutor

from fastapi.testclient import TestClient
import pytest

from almostdone_server.repositories.catalog import PostgresCatalogRepository
from almostdone_server.repositories.postgres import PostgresStore
from .test_postgres import database, pytestmark, application, login


@pytest.fixture
def records(database):
    store = PostgresStore(database)
    code = 'refresh_' + uuid4().hex[:16]
    with store.transaction() as db:
        ingredient_id = db.execute(
            'INSERT INTO ingredients(code,name,kcal,protein,fat,carbs,package_g,package_price) '
            'VALUES (%s,%s,100,1,1,1,100,10) RETURNING id',
            (code, 'Refresh ingredient ' + code)).fetchone()['id']
        recipe_id = db.execute(
            'INSERT INTO recipes(title,servings,cook_time_min,no_cook) VALUES (%s,2,1,true) RETURNING id',
            ('Refresh recipe ' + code,)).fetchone()['id']
        db.execute('INSERT INTO recipe_ingredients(recipe_id,ingredient_id,qty_g) VALUES (%s,%s,100)',
                   (recipe_id, ingredient_id))
        db.execute('INSERT INTO recipe_steps(recipe_id,step_no,instruction) VALUES (%s,1,%s)',
                   (recipe_id, 'Original step'))
    try:
        yield store, ingredient_id, recipe_id, code
    finally:
        with store.transaction() as db:
            db.execute('DELETE FROM recipes WHERE id=%s', (recipe_id,))
            db.execute('DELETE FROM ingredients WHERE id=%s AND code=%s', (ingredient_id, code))


def test_catalog_response_does_not_wait_for_user_row_lock(database):
    app = application(database)
    with TestClient(app) as client:
        headers, session = login(client)
        assert client.get('/api/v1/catalog', headers=headers).status_code == 200
        with ThreadPoolExecutor(max_workers=1) as pool:
            with app.state.service.store.transaction() as db:
                db.execute('SELECT id FROM users WHERE id=%s FOR UPDATE', (int(session['user_id']),))
                # A state read would block here until lock_timeout. A catalogue
                # response only authenticates the session and must finish now.
                response = pool.submit(client.get, '/api/v1/catalog', headers=headers).result(timeout=2)
                assert response.status_code == 200
                assert 'etag' not in response.headers


def test_background_worker_updates_export_and_search_without_restart(database, records):
    store, ingredient_id, recipe_id, code = records
    app = application(database)
    with TestClient(app) as client:
        headers, _ = login(client)
        first = client.get('/api/v1/catalog', headers=headers)
        assert first.status_code == 200
        original_version = first.json()['catalog_version']
        alias = 'newalias' + uuid4().hex[:12]
        with store.transaction() as db:
            db.execute('UPDATE ingredients SET name=%s,kcal=200 WHERE id=%s', ('Updated ingredient ' + code, ingredient_id))
            db.execute('UPDATE recipes SET title=%s WHERE id=%s', ('Updated recipe ' + code, recipe_id))
            db.execute('UPDATE recipe_steps SET instruction=%s WHERE recipe_id=%s', ('Updated step', recipe_id))
            db.execute('INSERT INTO ingredient_aliases(ingredient_id,alias) VALUES (%s,%s)', (ingredient_id, alias))
        deadline = time.monotonic() + 30
        while True:
            response = client.get('/api/v1/catalog', headers=headers)
            assert response.status_code == 200
            updated = response.json()
            if updated['catalog_version'] != original_version:
                break
            assert time.monotonic() < deadline, 'Background catalogue refresh did not finish'
            time.sleep(.25)
        ingredient = next(i for i in updated['ingredients'] if i['id'] == code)
        recipe = next(r for r in updated['recipes'] if r['id'] == str(recipe_id))
        assert ingredient['name'] == 'Updated ingredient ' + code
        assert ingredient['nutrition_per_100g']['kcal'] == 200
        assert recipe['title'] == 'Updated recipe ' + code
        assert recipe['steps'] == ['Updated step']
        search = client.get('/api/v1/ingredients', params={'q': alias}, headers=headers)
        assert search.status_code == 200
        assert code in {i['id'] for i in search.json()['items']}


def test_rollback_does_not_change_catalogue_revision(records):
    store, ingredient_id, _, _ = records
    repository = PostgresCatalogRepository(store)
    before = repository.revision()
    with pytest.raises(RuntimeError):
        with store.transaction() as db:
            db.execute('UPDATE ingredients SET kcal=kcal+1 WHERE id=%s', (ingredient_id,))
            raise RuntimeError('Rollback test change')
    assert repository.revision() == before


def test_all_catalogue_dependencies_have_statement_triggers(records):
    store, _, _, _ = records
    with store.transaction() as db:
        rows = db.execute("SELECT c.relname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid "
                          "WHERE t.tgname='invalidate_catalog' AND NOT t.tgisinternal")
        assert {r['relname'] for r in rows} == {
            'ingredients', 'ingredient_aliases', 'ingredient_allergens', 'allergens',
            'recipes', 'recipe_ingredients', 'recipe_steps', 'cooking_methods', 'recipe_cooking_methods',
        }


def test_notification_is_delivered_only_after_commit(records):
    store, ingredient_id, _, _ = records
    repository = PostgresCatalogRepository(store)

    async def check():
        async with repository.listen() as notifications:
            waiting = asyncio.create_task(anext(notifications))
            try:
                await asyncio.sleep(0)
                with store.psycopg.connect(store.dsn) as writer:
                    writer.execute('UPDATE ingredients SET kcal=kcal+1 WHERE id=%s', (ingredient_id,))
                    await asyncio.sleep(.1)
                    assert not waiting.done(), 'Uncommitted change invalidated the cache'
                    writer.rollback()
                    await asyncio.sleep(.1)
                    assert not waiting.done(), 'Rolled-back change invalidated the cache'
                    writer.execute('UPDATE ingredients SET kcal=kcal+1 WHERE id=%s', (ingredient_id,))
                    writer.commit()
                    notification = await asyncio.wait_for(waiting, timeout=5)
                    assert notification.channel == 'almostdone_catalog_changed'
            finally:
                waiting.cancel()
                await asyncio.gather(waiting, return_exceptions=True)

    asyncio.run(check())


def test_listener_does_not_poll_revision_while_idle(database, records, monkeypatch):
    app = application(database)
    repository = app.state.service.catalog._repository
    original = repository.revision
    initial_check = Event()
    checks = []

    def revision():
        checks.append(True)
        result = original()
        initial_check.set()
        return result

    monkeypatch.setattr(repository, 'revision', revision)
    with TestClient(app):
        assert initial_check.wait(5)
        time.sleep(5.3)
        assert len(checks) == 1, 'Idle listener must not poll the database'


def test_reconnect_catches_changes_committed_while_disconnected(database, records, monkeypatch):
    store, ingredient_id, _, code = records
    app = application(database)
    repository = app.state.service.catalog._repository
    original = repository.listen
    disconnected = Event()
    subscriptions = []

    @asynccontextmanager
    async def listen():
        first = not subscriptions
        subscriptions.append(True)
        try:
            async with original() as notifications:
                if first:
                    async def broken_connection():
                        raise ConnectionError('Synthetic disconnect')
                        yield

                    async with aclosing(broken_connection()) as broken:
                        yield broken
                else:
                    yield notifications
        finally:
            if first:
                disconnected.set()

    monkeypatch.setattr(repository, 'listen', listen)
    with TestClient(app) as client:
        assert disconnected.wait(5)
        with store.transaction() as db:
            db.execute('UPDATE ingredients SET name=%s WHERE id=%s', ('Changed while offline ' + code, ingredient_id))
        headers, _ = login(client)
        deadline = time.monotonic() + 20
        while True:
            response = client.get('/api/v1/catalog', headers=headers)
            assert response.status_code == 200
            ingredient = next(i for i in response.json()['ingredients'] if i['id'] == code)
            if ingredient['name'] == 'Changed while offline ' + code:
                break
            assert time.monotonic() < deadline, 'Reconnect missed a committed catalogue change'
            time.sleep(.25)
        assert len(subscriptions) >= 2
