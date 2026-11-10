"""Session policies and rollback tested without opening network connections."""
import copy

import pytest

from almostdone_server.errors import APIError, StorageUnavailable
from almostdone_server.repositories.memory import Store
from almostdone_server.repositories.postgres import PostgresStore
from almostdone_server.services.auth import AuthService


class Rows(list):
    def fetchone(self):
        return self[0] if self else None


@pytest.fixture(params=["memory", "postgres"])
def sessions(request, monkeypatch):
    fault = {"commit": False}
    if request.param == "memory":
        store = Store()
    else:
        psycopg = pytest.importorskip("psycopg")
        store = PostgresStore("not-a-real-database")

        class Connection:
            def __enter__(self):
                return self

            def __exit__(self, exception_type, *args):
                if exception_type is None and fault["commit"]:
                    raise psycopg.OperationalError("simulated commit failure")

            def execute(self, sql, params=()):
                if sql.startswith("SELECT id,pevzner_diet_id"):
                    return Rows([{"id": 1, "pevzner_diet_id": None}])
                return Rows()

        monkeypatch.setattr(store.psycopg, "connect", lambda *args, **kwargs: Connection())
    auth = AuthService(store, {})
    with store.transaction() as db:
        original = auth.issue(db, "1")
    return store, auth, original, fault


@pytest.mark.parametrize("failure", [APIError(500, "internal_error", "Rejected response"), ValueError("Rejected response")])
def test_refresh_output_validation_failure_preserves_old_session(sessions, failure):
    store, auth, original, _ = sessions
    before = copy.deepcopy(store.runtime._data)

    def reject(result):
        assert result.data["refresh_token"] != original["refresh_token"]
        raise failure

    with pytest.raises(type(failure)):
        auth.refresh(original["refresh_token"], reject)
    assert store.runtime._data == before
    with store.transaction() as db:
        assert auth.authenticate(db, original["access_token"])["user_id"] == "1"
    assert auth.refresh(original["refresh_token"], lambda result: None).data["access_token"]


def test_refresh_is_published_only_after_validation(sessions):
    store, auth, original, _ = sessions
    before = copy.deepcopy(store.runtime._data)

    def validate(result):
        assert result.data["access_token"] != original["access_token"]
        assert store.runtime._data == before

    updated = auth.refresh(original["refresh_token"], validate)
    with store.transaction() as db:
        assert auth.authenticate(db, updated.data["access_token"])["user_id"] == "1"
        with pytest.raises(APIError):
            auth.authenticate(db, original["access_token"])


def test_refresh_reuse_commits_family_revocation_despite_rejection(sessions):
    store, auth, original, _ = sessions
    updated = auth.refresh(original["refresh_token"], lambda result: None)
    with pytest.raises(APIError) as error:
        auth.refresh(original["refresh_token"], lambda result: None)
    assert error.value.code == "session_expired"
    with store.transaction() as db:
        with pytest.raises(APIError):
            auth.authenticate(db, updated.data["access_token"])


@pytest.mark.parametrize("sessions", ["postgres"], indirect=True)
def test_sql_commit_failure_preserves_old_refresh_and_access_tokens(sessions):
    store, auth, original, fault = sessions
    before = copy.deepcopy(store.runtime._data)
    fault["commit"] = True
    with pytest.raises(StorageUnavailable):
        auth.refresh(original["refresh_token"], lambda result: None)
    assert store.runtime._data == before
    fault["commit"] = False
    with store.transaction() as db:
        assert auth.authenticate(db, original["access_token"])["user_id"] == "1"
    assert auth.refresh(original["refresh_token"], lambda result: None).data["access_token"]
