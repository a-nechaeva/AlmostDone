"""Lifetimes, ownership and retry policies for temporary application resources."""
import time
from uuid import uuid4

from ..errors import APIError


class RuntimeService:
    def __init__(self, store):
        self.records = store.runtime

    def replay(self, db, user_id, scope, key, fingerprint):
        row = self.records.get(db.runtime, "replays", (user_id, scope, key))
        if row is None or row["expires"] <= time.time():
            return None
        if row["fingerprint"] != fingerprint:
            raise APIError(409, "idempotency_conflict", "Ключ уже использован с другим запросом")
        return row["result"]

    def record(self, db, user_id, scope, key, fingerprint, result):
        ttl = 86400 if scope == "recognitions_create" else 30 * 86400
        self.records.put(db.runtime, "replays", (user_id, scope, key),
                         {"fingerprint": fingerprint, "result": result, "expires": time.time() + ttl})

    def put_object(self, db, user_id, kind, body, ttl):
        identifier = str(uuid4())
        self.records.put(db.runtime, "objects", identifier,
                         {"user_id": user_id, "kind": kind, "body": body, "expires": time.time() + ttl})
        return identifier

    def update_object(self, db, identifier, body):
        row = self.records.get(db.runtime, "objects", identifier)
        row["body"] = body
        self.records.put(db.runtime, "objects", identifier, row)

    def get_object(self, db, identifier, user_id, kind):
        row = self.records.get(db.runtime, "objects", identifier)
        if row is None or row["user_id"] != user_id or row["kind"] != kind:
            raise APIError(404, "not_found", "Ресурс не найден")
        if row["expires"] <= time.time():
            if kind == "snapshot":
                raise APIError(409, "snapshot_expired", "Снимок подбора истёк")
            raise APIError(404, "not_found", "Результат распознавания истёк")
        return row["body"], row["expires"]

    def previous_import(self, db, recognition_id):
        return self.records.get(db.runtime, "imports", recognition_id)

    def record_import(self, db, recognition_id, user_id, operation_id):
        self.records.put(db.runtime, "imports", recognition_id, {"user_id": user_id, "operation_id": operation_id})

    def purge(self, db):
        now = time.time()
        for key, row in self.records.items(db.runtime, "objects"):
            if row["expires"] <= now:
                if row["kind"] == "snapshot":
                    row["body"] = {}  # Preserve ownership for snapshot_expired.
                    self.records.put(db.runtime, "objects", key, row)
                else:
                    self.records.delete(db.runtime, "objects", key)
        for key, row in self.records.items(db.runtime, "replays"):
            if row["expires"] <= now:
                self.records.delete(db.runtime, "replays", key)
