"""Recommendations application use cases; no HTTP request handling."""
import copy

from ..errors import APIError, invalid
from .models import ALLERGENS
from .pagination import iso


class RecommendationService:
    def __init__(self, runtime, catalog, pagination):
        self.runtime, self.catalog, self.pagination = runtime, catalog, pagination

    def execute(self, db, uid, user, session, oid, body, params):
        if oid == "recommendations_create":
            if set(body["filters"]["exclude_allergens"]) - set(ALLERGENS):
                raise invalid("Неизвестный аллерген", "filters.exclude_allergens")
            matches = self.catalog.matches(user, body["filters"], body["servings"])
            visible = [d for d, _ in matches if d["recipe"]["suitability"]["status"] != "hidden"]
            hidden = [d for d, _ in matches if d["recipe"]["suitability"]["status"] == "hidden"]
            snapshot = {"request_id": body["request_id"], "state_version": user["version"],
                        "catalog_version": self.catalog.version, "visibility": body["visibility"],
                        "servings": body["servings"], "filters": copy.deepcopy(body["filters"]),
                        "dietary_version": user.get("_dietary", {}).get("version"),
                        "visible_total": len(visible), "hidden_total": len(hidden),
                        "unknown_total": sum(d["recipe"]["suitability"]["status"] == "unknown" for d in visible),
                        "details": visible if body["visibility"] == "visible" else hidden, "limit": body["limit"],
                        "engine_options": [self.catalog.gateway.serialize_option(option) for detail, option in matches if option is not None and
                                           (detail["recipe"]["suitability"]["status"] != "hidden") == (body["visibility"] == "visible")]}
            sid = self.runtime.put_object(db, uid, "snapshot", snapshot, 600)
            _, expires = self.runtime.get_object(db, sid, uid, "snapshot")
            return self.snapshot_page(db, uid, user, sid, snapshot, expires)
        if oid in ("recommendations_page", "recommendations_graph"):
            sid = params["snapshot_id"]
            snapshot, expires = self.runtime.get_object(db, sid, uid, "snapshot")
            if (snapshot["state_version"] != user["version"] or snapshot["catalog_version"] != self.catalog.version
                    or snapshot.get("dietary_version") != user.get("_dietary", {}).get("version")):
                raise APIError(409, "context_changed", "Состояние снимка устарело")
            if oid == "recommendations_graph":
                result = {k: snapshot[k] for k in ("request_id", "state_version", "catalog_version", "servings", "filters", "visibility")}
                return {**result, "snapshot_id": sid, "expires_at": iso(expires),
                        "graph": self.catalog.graph(snapshot["details"], [self.catalog.gateway.restore_option(value)
                                                                          for value in snapshot["engine_options"]])}
            return self.snapshot_page(db, uid, user, sid, snapshot, expires, params.get('cursor'))
        if oid in ("purchases_single_purchase", "purchases_budget"):
            return self.catalog.purchases(user, body, oid.endswith('single_purchase'))
        raise ValueError(f"Unsupported operation: {oid}")

    def snapshot_page(self, db, uid, user, sid, snapshot, expires, cursor=None):
        details, page = self.pagination.paginate(db, uid, user, "snapshot:" + sid,
                                     {"limit": snapshot["limit"], "cursor": cursor}, snapshot["details"])
        body = {k: v for k, v in snapshot.items() if k not in ("details", "limit", "filters", "engine_options", "dietary_version")}
        return {**body, "snapshot_id": sid, "expires_at": iso(expires),
                "items": [d["recipe"] for d in details], "page": page}
