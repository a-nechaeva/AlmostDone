import time
from uuid import uuid4

import pytest

from almostdone_server.errors import APIError
from ..support.memory import Store
from almostdone_server.services.auth import AuthService
from almostdone_server.services.runtime import RuntimeService


def test_recognition_replays_do_not_extend_raw_result_retention(monkeypatch):
    now = [time.time()]
    monkeypatch.setattr("almostdone_server.services.runtime.time.time", lambda: now[0])
    store = Store()
    runtime = RuntimeService(store)
    auth = AuthService(store, {})
    key = str(uuid4())
    with store.transaction() as db:
        runtime.record(db, "alice", "recognitions_create", key, "fingerprint", {"raw": "result"})
        runtime.record(db, "alice", "recognitions_import", key, "fingerprint", {"pantry": []})
        snapshot = runtime.put_object(db, "alice", "snapshot", {"details": ["large-recipe-data"]}, 600)
    now[0] += 86401
    with store.transaction() as db:
        runtime.purge(db)
        auth.purge(db)
    with store.transaction() as db:
        assert runtime.replay(db, "alice", "recognitions_create", key, "fingerprint") is None
        assert runtime.replay(db, "alice", "recognitions_import", key, "fingerprint") is not None
        assert store.runtime.get(db.runtime, "objects", snapshot)["body"] == {}
        with pytest.raises(APIError) as error:
            runtime.get_object(db, snapshot, "alice", "snapshot")
        assert error.value.status == 409 and error.value.code == "snapshot_expired"


def test_expired_refresh_does_not_shorten_the_issued_access_token(monkeypatch):
    now = [time.time()]
    monkeypatch.setattr("almostdone_server.services.runtime.time.time", lambda: now[0])
    store = Store()
    runtime = RuntimeService(store)
    auth = AuthService(store, {})
    with store.transaction() as db:
        session = auth.issue(db, "alice", refresh_until=now[0] + 1)
    now[0] += 2
    with store.transaction() as db:
        runtime.purge(db)
        auth.purge(db)
    with store.transaction() as db:
        assert auth.authenticate(db, session["access_token"])["user_id"] == "alice"
