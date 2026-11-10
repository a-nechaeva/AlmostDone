"""Application cursors and snapshot timestamps."""
from datetime import datetime, timezone

from ..errors import APIError


def iso(timestamp):
    return datetime.fromtimestamp(timestamp, timezone.utc).isoformat().replace("+00:00", "Z")


class Pagination:
    def __init__(self, runtime, catalog):
        self.runtime, self.catalog = runtime, catalog

    def paginate(self, db, uid, user, scope, params, items, signature=""):
        limit, offset = params.get("limit", 20), 0
        if params.get("cursor"):
            try:
                cursor, _ = self.runtime.get_object(db, params["cursor"], uid, "cursor")
            except APIError:
                raise APIError(409, "context_changed", "Недействительный cursor") from None
            expected = (scope, user["version"], self.catalog.version, signature, limit)
            actual = tuple(cursor[k] for k in ("scope", "version", "catalog", "signature", "limit"))
            if actual != expected:
                raise APIError(409, "context_changed", "Контекст cursor изменился")
            offset = cursor["offset"]
        more = offset + limit < len(items)
        next_cursor = None
        if more:
            next_cursor = self.runtime.put_object(db, uid, "cursor", {
                "scope": scope, "version": user["version"], "catalog": self.catalog.version,
                "signature": signature, "limit": limit, "offset": offset + limit}, 600)
        return items[offset:offset + limit], {"next_cursor": next_cursor, "has_more": more}
