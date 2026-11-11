"""Application state versions, preferences and original display quantities."""
import copy
import hashlib
import json
from decimal import Decimal

from ..errors import APIError
from .models import default_user


class UserStateService:
    def __init__(self, store, catalog=None):
        self.store, self.catalog, self.records = store, catalog, store.runtime

    def grams(self, code, quantity):
        if quantity is None:
            return None
        if quantity["unit"] == "g":
            factor = 1
        else:
            ingredient = self.catalog.ingredients[code] if self.catalog else {}
            factor = ingredient.get("grams_per_ml" if quantity["unit"] == "ml" else "grams_per_piece")
        if not factor:
            raise APIError(409, "unit_conflict", "Нет коэффициента перевода в граммы")
        return Decimal(str(quantity["value"])) * Decimal(str(factor))

    def load(self, db, user_id):
        stored = self.store.user(db, user_id)
        if stored is None:
            if self.store.persistent:
                raise APIError(401, "session_expired", "Пользователь не найден")
            stored = default_user()
            stored.pop("version")
            self.store.save(db, user_id, stored)
        metadata = self.store.api_state(db, user_id) if self.store.persistent else None
        previous = self.records.get(db.runtime, "states", user_id) if not self.store.persistent else None
        state = default_user()
        state.update(copy.deepcopy(stored))
        prefs = {**default_user()["preferences"], **stored.get("preferences", {})}
        prefs["excluded_allergens"].sort()
        state["preferences"] = prefs
        if metadata:
            prefs["diabetes"] = metadata["diabetes"]
            state["version"] = metadata["state_version"]
            for code, quantity in state["pantry"].items():
                old = metadata["pantry_display"].get(code)
                if old and quantity and self.grams(code, old) == Decimal(str(quantity["value"])):
                    state["pantry"][code] = copy.deepcopy(old)
        if previous:
            state["version"] = previous["version"]
            if state != previous:
                state["version"] += 1
        if metadata:
            state_hash = self.fingerprint(state)
            if metadata["state_hash"] is not None and metadata["state_hash"] != state_hash:
                state["version"] += 1
            self.store.save_api_state(db, user_id, state, state_hash)
        else:
            self.records.put(db.runtime, "states", user_id, state)
        return state

    @staticmethod
    def fingerprint(state):
        content = copy.deepcopy({key: value for key, value in state.items() if key != "version"})
        for quantity in content["pantry"].values():
            if quantity is not None:
                quantity["value"] = float(quantity["value"])
        return hashlib.sha256(json.dumps(content, sort_keys=True, allow_nan=False).encode()).hexdigest()

    def save(self, db, user_id, state):
        state["preferences"]["excluded_allergens"].sort()
        stored = copy.deepcopy(state)
        stored.pop("version")
        if self.store.persistent:
            # Domain tables store mass; API metadata preserves preference and unit.
            stored["preferences"].pop("diabetes", None)
            stored["pantry"] = {code: None if quantity is None else
                                {"value": self.grams(code, quantity), "unit": "g"}
                                for code, quantity in state["pantry"].items()}
        self.store.save(db, user_id, stored)
        if self.store.persistent:
            self.store.save_api_state(db, user_id, state, self.fingerprint(state))
        else:
            self.records.put(db.runtime, "states", user_id, state)
