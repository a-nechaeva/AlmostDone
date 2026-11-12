"""Stateful test storage; never used as the server's default database."""
import copy
import threading
from contextlib import contextmanager

from almostdone_server.repositories.records import Transaction


class MemoryRecords:
    def __init__(self):
        self._lock = threading.RLock()
        self._data = {}

    @contextmanager
    def transaction(self):
        with self._lock:
            working = copy.deepcopy(self._data)
            yield working
            self._data = working

    @staticmethod
    def get(data, collection, key):
        return copy.deepcopy(data.get(collection, {}).get(key))

    @staticmethod
    def put(data, collection, key, value):
        data.setdefault(collection, {})[key] = copy.deepcopy(value)

    @staticmethod
    def delete(data, collection, key):
        data.get(collection, {}).pop(key, None)

    @staticmethod
    def items(data, collection):
        return list(copy.deepcopy(data.get(collection, {})).items())

    def session_by_refresh(self, data, refresh_hash):
        return next(((key, row) for key, row in self.items(data, "sessions")
                     if row["refresh_hash"] == refresh_hash), None)

    def revoke_family(self, data, family):
        for key, row in self.items(data, "sessions"):
            if row["family"] == family:
                row["revoked"] = True
                self.put(data, "sessions", key, row)


class Store:
    mode = "memory-stub"
    persistent = False

    def dietary_support(self, db):
        return set()

    def dietary_visibility(self, db, user_id):
        return {}

    def check_health(self):
        with self.transaction():
            pass

    def __init__(self):
        self.runtime = MemoryRecords()

    @contextmanager
    def transaction(self):
        with self.runtime.transaction() as records:
            yield Transaction(records)

    def identity(self, db, login, password_marker):
        row = self.runtime.get(db.runtime, "identities", login)
        if row is None:
            row = {"id": login, "password_hash": password_marker}
            self.runtime.put(db.runtime, "identities", login, row)
        return row

    def user(self, db, user_id):
        return self.runtime.get(db.runtime, "users", user_id)

    def save(self, db, user_id, state):
        self.runtime.put(db.runtime, "users", user_id, state)
