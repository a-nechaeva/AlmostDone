"""Application state versions and process-local preferences and display units."""
import copy
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
        previous = self.records.get(db.runtime, "states", user_id)
        state = default_user()
        state.update(copy.deepcopy(stored))
        prefs = {**default_user()["preferences"], **stored.get("preferences", {})}
        prefs["excluded_allergens"].sort()
        state["preferences"] = prefs
        if self.store.persistent and previous:
            prefs["diabetes"] = previous["preferences"]["diabetes"]
            for code, quantity in state["pantry"].items():
                old = previous["pantry"].get(code)
                if old and quantity and self.grams(code, old) == Decimal(str(quantity["value"])):
                    state["pantry"][code] = copy.deepcopy(old)
        if previous:
            state["version"] = previous["version"]
            if state != previous:
                state["version"] += 1
        self.records.put(db.runtime, "states", user_id, state)
        return state

    def save(self, db, user_id, state):
        state["preferences"]["excluded_allergens"].sort()
        stored = copy.deepcopy(state)
        stored.pop("version")
        if self.store.persistent:
            stored["preferences"].pop("diabetes", None)
            stored["pantry"] = {code: None if quantity is None else
                                {"value": self.grams(code, quantity), "unit": "g"}
                                for code, quantity in state["pantry"].items()}
        self.store.save(db, user_id, stored)
        self.records.put(db.runtime, "states", user_id, state)
