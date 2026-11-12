"""Session policies and rollback tested without opening network connections."""
import copy

import pytest

from almostdone_server.errors import APIError
from ..support.memory import Store
from almostdone_server.services.auth import AuthService


@pytest.fixture
def sessions():
    # PostgreSQL rollback/rotation now uses real independent connections in
    # repositories/test_postgres_persistence.py, rather than a memory-backed fake.
    store = Store()
    auth = AuthService(store, {})
    with store.transaction() as db:
        original = auth.issue(db, "1")
    return store, auth, original


@pytest.mark.parametrize("failure", [APIError(500, "internal_error", "Rejected response"), ValueError("Rejected response")])
def test_refresh_output_validation_failure_preserves_old_session(sessions, failure):
    store, auth, original = sessions
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
    store, auth, original = sessions
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
    store, auth, original = sessions
    updated = auth.refresh(original["refresh_token"], lambda result: None)
    with pytest.raises(APIError) as error:
        auth.refresh(original["refresh_token"], lambda result: None)
    assert error.value.code == "session_expired"
    with store.transaction() as db:
        with pytest.raises(APIError):
            auth.authenticate(db, updated.data["access_token"])
