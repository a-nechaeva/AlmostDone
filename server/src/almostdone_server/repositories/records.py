"""Transactional in-memory records. Callers provide keys, values and policies."""
import copy
import threading
from contextlib import contextmanager


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


class Transaction:
    def __init__(self, runtime, connection=None):
        self.runtime = runtime
        self.connection = connection

    def execute(self, *args, **kwargs):
        return self.connection.execute(*args, **kwargs)
