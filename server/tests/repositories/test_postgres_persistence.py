"""Durability, transaction boundaries and concurrency on a real migrated database."""
import hashlib
import json
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from almostdone_server.errors import APIError, StorageUnavailable
from almostdone_server.services.commands import Command
from ..support.catalog import custom_catalog
from ..support.http import FILTERS, mutation
from .test_postgres import application, database, login, pytestmark


def test_refresh_and_logout_survive_independent_server_restarts(database):
    with TestClient(application(database)) as client:
        _, original = login(client)
    with TestClient(application(database)) as client:
        response = client.post('/api/v1/auth/refresh', json={'refresh_token': original['refresh_token']})
        assert response.status_code == 200, response.text
        rotated = response.json()
        active = {'Authorization': 'Bearer ' + rotated['access_token']}
        assert client.get('/api/v1/me', headers={'Authorization': 'Bearer ' + original['access_token']}).status_code == 401
        assert client.post('/api/v1/auth/logout', headers=active).status_code == 204
    with TestClient(application(database)) as client:
        assert client.get('/api/v1/me', headers=active).status_code == 401
        assert client.post('/api/v1/auth/refresh', json={'refresh_token': rotated['refresh_token']}).status_code == 401


def test_concurrent_refresh_issues_only_one_pair_and_reuse_revokes_it(database):
    first, second = application(database), application(database)
    with TestClient(first) as left, TestClient(second) as right:
        _, original = login(left)
        barrier = Barrier(2)

        def refresh(client):
            barrier.wait()
            return client.post('/api/v1/auth/refresh', json={'refresh_token': original['refresh_token']})

        with ThreadPoolExecutor(max_workers=2) as pool:
            responses = list(pool.map(refresh, (left, right)))
        assert sorted(r.status_code for r in responses) == [200, 401]
        pair = next(r.json() for r in responses if r.status_code == 200)
        assert left.get('/api/v1/me', headers={'Authorization': 'Bearer ' + pair['access_token']}).status_code == 401


def test_refresh_works_after_access_has_expired(database):
    app = application(database)
    with TestClient(app) as client:
        headers, session = login(client)
        with app.state.service.store.transaction() as db:
            db.execute("""UPDATE auth_tokens SET created_at=now()-interval '1 hour',
                          access_expires_at=now()-interval '1 minute' WHERE access_token_hash=%s""",
                       (hashlib.sha256(session['access_token'].encode()).hexdigest(),))
        assert client.get('/api/v1/me', headers=headers).status_code == 401
    with TestClient(application(database)) as client:
        response = client.post('/api/v1/auth/refresh', json={'refresh_token': session['refresh_token']})
        assert response.status_code == 200, response.text
        active = {'Authorization': 'Bearer ' + response.json()['access_token']}
        assert client.get('/api/v1/me', headers=active).status_code == 200


def test_legacy_identity_is_linked_without_creating_another_user(database):
    app = application(database)
    service = app.state.service
    subject = 'legacy-' + uuid4().hex
    fingerprint = hashlib.sha256(json.dumps(['yandex', subject], ensure_ascii=False).encode()).hexdigest()
    with service.store.transaction() as db:
        row = service.store.identity(db, 'oauth_' + fingerprint[:26], '!oauth-only:' + fingerprint)
        old_id = str(row['id'])
    with TestClient(app) as client:
        _, session = login(client, subject)
        assert session['user_id'] == old_id
    with service.store.transaction() as db:
        assert db.execute('SELECT user_id FROM user_identities WHERE provider=%s AND provider_subject=%s',
                          ('yandex', subject)).fetchone()['user_id'] == int(old_id)
        pair = db.execute('SELECT access_token_hash,refresh_token_hash FROM auth_tokens t JOIN auth_sessions s ON s.id=t.session_id WHERE s.user_id=%s',
                          (old_id,)).fetchone()
        assert pair['access_token_hash'] == hashlib.sha256(session['access_token'].encode()).hexdigest()
        assert pair['refresh_token_hash'] == hashlib.sha256(session['refresh_token'].encode()).hexdigest()


def test_preferences_display_units_and_external_change_detection_survive_restart(database):
    # The current seed has no usable pcs conversion. Exercise display metadata
    # with a supplied catalogue, while storing mass in the real SQL pantry.
    code = next(iter(application(database).state.service.catalog.ingredients))
    data = custom_catalog()
    data['ingredients'][0].update(code=code, display_unit='pcs', grams_per_piece=100)
    for recipe in data['recipes']:
        for item in recipe['items']:
            if item['code'] == 'rice':
                item['code'] = code
    app = application(database, catalog_data=data)
    with TestClient(app) as client:
        headers, session = login(client)
        prefs = client.get('/api/v1/me', headers=headers).json()['preferences']
        prefs['diabetes'] = True
        assert client.patch('/api/v1/me', json={'preferences': prefs}, headers=mutation(client, headers)).status_code == 200
        response = client.post('/api/v1/me/pantry/add', json={'ingredient_id': code, 'quantity': {'value': 1, 'unit': 'pcs'}},
                               headers=mutation(client, headers))
        assert response.status_code == 200, response.text
        version = response.json()['state_version']
    restarted = application(database, catalog_data=data)
    with TestClient(restarted) as client:
        assert client.get('/api/v1/me', headers=headers).json()['preferences']['diabetes'] is True
        pantry = client.get('/api/v1/me/pantry', headers=headers).json()
        assert pantry['state_version'] == version
        assert pantry['items'][0]['quantity'] == {'value': 1, 'unit': 'pcs'}
        with restarted.state.service.store.transaction() as db:
            db.execute('UPDATE user_pantry SET qty_g=qty_g+1 WHERE user_id=%s', (session['user_id'],))
        changed = client.get('/api/v1/me/pantry', headers=headers).json()
        assert changed['state_version'] == version + 1
        assert changed['items'][0]['quantity']['unit'] == 'g'
        assert client.get('/api/v1/me/state', headers=headers).json()['state_version'] == version + 1


def test_snapshot_cursor_and_graph_are_durable_and_owned(database):
    data = custom_catalog()
    with TestClient(application(database, catalog_data=data)) as client:
        headers, _ = login(client)
        body = {'request_id': str(uuid4()), 'servings': 2, 'filters': FILTERS, 'visibility': 'visible', 'limit': 1}
        response = client.post('/api/v1/recommendations', json=body, headers=headers)
        assert response.status_code == 201, response.text
        page = response.json()
        path = '/api/v1/recommendations/' + page['snapshot_id']
        graph = client.get(path + '/graph', headers=headers)
        assert graph.status_code == 200, graph.text
    with TestClient(application(database, catalog_data=data)) as client:
        assert client.get(path + '/graph', headers=headers).json() == graph.json()
        second = client.get(path, params={'cursor': page['page']['next_cursor']}, headers=headers)
        assert second.status_code == 200, second.text
        assert second.json()['items'][0]['id'] != page['items'][0]['id']
        other, _ = login(client)
        assert client.get(path, headers=other).status_code == 404
        assert client.get('/api/v1/recommendations/not-a-uuid', headers=headers).status_code == 404


def test_concurrent_identical_mutations_commit_once_across_stores(database):
    first, second = application(database), application(database)
    code = next(iter(first.state.service.catalog.ingredients))
    with TestClient(first) as left, TestClient(second) as right:
        headers, _ = login(left)
        command_headers = mutation(left, headers)
        body = {'ingredient_id': code, 'quantity': {'value': 100, 'unit': 'g'}}
        barrier = Barrier(2)

        def add(client):
            barrier.wait()
            return client.post('/api/v1/me/pantry/add', json=body, headers=command_headers)

        with ThreadPoolExecutor(max_workers=2) as pool:
            responses = list(pool.map(add, (left, right)))
        assert [r.status_code for r in responses] == [200, 200]
        assert responses[0].json() == responses[1].json()
        assert left.get('/api/v1/me/pantry', headers=headers).json()['items'][0]['quantity']['value'] == 100


def test_output_validation_rolls_back_domain_state_and_retry_record(database):
    app = application(database)
    service = app.state.service
    with TestClient(app) as client:
        headers, session = login(client)
    code = next(iter(service.catalog.ingredients))
    command = Command('pantry_add', {'ingredient_id': code, 'quantity': {'value': 100, 'unit': 'g'}},
                      access_token=session['access_token'], expected_version=0, idempotency_key=str(uuid4()))

    def reject(result):
        raise APIError(500, 'internal_error', 'Rejected response')

    with pytest.raises(APIError):
        service.execute(command, reject)
    with service.store.transaction() as db:
        assert db.execute('SELECT count(*) AS n FROM user_pantry WHERE user_id=%s', (session['user_id'],)).fetchone()['n'] == 0
        assert db.execute('SELECT count(*) AS n FROM api_idempotency WHERE user_id=%s', (session['user_id'],)).fetchone()['n'] == 0
    assert service.execute(command).version == 1


def test_refresh_validation_and_failed_commit_preserve_original_tokens(database, monkeypatch):
    app = application(database)
    service = app.state.service
    with TestClient(app) as client:
        _, original = login(client)

    def reject(result):
        raise APIError(500, 'internal_error', 'Rejected refresh response')

    with pytest.raises(APIError):
        service.auth.refresh(original['refresh_token'], reject)
    connect = service.store.psycopg.connect

    class FailedCommit:
        def __init__(self, connection):
            self.connection = connection

        def __enter__(self):
            return self.connection.__enter__()

        def __exit__(self, exc_type, exc, traceback):
            if exc_type is None:
                failure = service.store.psycopg.OperationalError('simulated commit failure')
                self.connection.__exit__(type(failure), failure, None)
                raise failure
            return self.connection.__exit__(exc_type, exc, traceback)

    with monkeypatch.context() as patch:
        patch.setattr(service.store.psycopg, 'connect', lambda *a, **kw: FailedCommit(connect(*a, **kw)))
        with pytest.raises(StorageUnavailable):
            service.auth.refresh(original['refresh_token'], lambda result: None)
    with service.store.transaction() as db:
        assert service.auth.authenticate(db, original['access_token'])['user_id'] == original['user_id']
        assert db.execute('SELECT count(*) AS n FROM auth_tokens t JOIN auth_sessions s ON s.id=t.session_id WHERE s.user_id=%s',
                          (original['user_id'],)).fetchone()['n'] == 1
    assert service.auth.refresh(original['refresh_token'], lambda result: None).data['access_token']


def test_cleanup_retains_import_marker_and_snapshot_expired_response(database):
    app = application(database)
    service = app.state.service
    with TestClient(app) as client:
        headers, session = login(client)
    with service.store.transaction() as db:
        uid = session['user_id']
        recognition = service.runtime.put_object(db, uid, 'recognition', {}, 86400)
        snapshot = service.runtime.put_object(db, uid, 'snapshot', {'large': 'data'}, 600)
        service.runtime.record_import(db, recognition, uid, str(uuid4()))
        db.execute("UPDATE api_resources SET created_at=now()-interval '2 days',expires_at=now()-interval '1 day' WHERE id IN (%s,%s)", (recognition, snapshot))
    service.purge()
    with service.store.transaction() as db:
        assert service.runtime.previous_import(db, recognition)['user_id'] == uid
        assert service.store.runtime.get(db.runtime, 'objects', recognition) is None
        with pytest.raises(APIError) as error:
            service.runtime.get_object(db, snapshot, uid, 'snapshot')
        assert error.value.code == 'snapshot_expired'
