"""User records and identities stored in memory, without application policies."""
from contextlib import contextmanager

from .records import MemoryRecords, Transaction


class Store:
    mode = "memory-stub"
    persistent = False

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
