"""Users application use cases; no HTTP request handling."""
import copy
from decimal import Decimal

from ..errors import APIError, invalid
from .models import ALLERGENS


class UserService:
    def __init__(self, catalog, pagination, dietary=None):
        self.catalog, self.pagination, self.dietary = catalog, pagination, dietary

    def pantry(self, user):
        return {"state_version": user["version"], "items": [
            {"ingredient_id": i, "name": self.catalog.ingredients[i]["name"], "quantity": q}
            for i, q in sorted(user["pantry"].items())]}

    def profile(self, uid, user, supported=()):
        preferences = user["preferences"]
        unsupported = ([preferences["food_type"]] if preferences["food_type"] != "any" else [])
        unsupported += [name for name in ("gluten_free", "lactose_free", "diabetes") if preferences[name]]
        if preferences["diet_table_id"]:
            unsupported.append(preferences["diet_table_id"])
        return {"user_id": uid, "display_name": None, "preferences": preferences,
                "unsupported_restrictions": [item for item in unsupported if item not in supported], "state_version": user["version"]}

    def add(self, user, ingredient_id, quantity):
        self.catalog.validate_quantity(ingredient_id, quantity)
        if ingredient_id not in user["pantry"]:
            user["pantry"][ingredient_id] = copy.deepcopy(quantity)
            return
        previous = user["pantry"][ingredient_id]
        if previous is None or quantity is None:
            user["pantry"][ingredient_id] = None
        elif previous["unit"] != quantity["unit"]:
            raise APIError(409, "unit_conflict", "Нельзя сложить несовместимые единицы")
        else:
            amount = float(Decimal(str(previous["value"])) + Decimal(str(quantity["value"])))
            if amount > 1_000_000:
                raise invalid("Итоговое количество превышает 1 000 000", "quantity", "invalid_quantity")
            user["pantry"][ingredient_id] = {"value": amount, "unit": previous["unit"]}

    def execute(self, db, uid, user, session, oid, body, params):
        if oid == "state_get":
            return {'state_version': user['version'], 'catalog_version': self.catalog.version, 'user_id': uid}
        if oid == "profile_save":
            prefs = body["preferences"]
            if set(prefs["excluded_allergens"]) - set(ALLERGENS):
                raise invalid("Неизвестный аллерген", "preferences.excluded_allergens")
            if prefs["diet_table_id"] is not None and prefs["diet_table_id"] not in {f"pevzner_{i}" for i in range(1, 16)}:
                raise invalid("Неизвестный диетический стол", "preferences.diet_table_id")
            user["preferences"] = copy.deepcopy(prefs)
            return self.profile(uid, user, self.dietary.supported(db) if self.dietary else ())
        if oid == "profile_get":
            return self.profile(uid, user, self.dietary.supported(db) if self.dietary else ())
        if oid == "pantry_get":
            return self.pantry(user)
        if oid == "pantry_add":
            self.add(user, body["ingredient_id"], body["quantity"])
            return self.pantry(user)
        if oid in ("pantry_set", "pantry_delete"):
            ingredient_id = params["ingredient_id"]
            self.catalog.ingredient(ingredient_id)
            if oid == "pantry_delete" or body["quantity"] is not None and body["quantity"]["value"] == 0:
                user["pantry"].pop(ingredient_id, None)
            else:
                self.catalog.validate_quantity(ingredient_id, body["quantity"])
                user["pantry"][ingredient_id] = copy.deepcopy(body["quantity"])
            return self.pantry(user)
        if oid == "pantry_add_purchased":
            ids = [item["ingredient_id"] for item in body["items"]]
            if len(ids) != len(set(ids)):
                raise invalid("Ингредиент повторяется в пакете", "items", "duplicate_ingredient")
            for item in body["items"]:
                self.add(user, item["ingredient_id"], item["quantity"])
            return self.pantry(user)
        if oid.startswith("favorites_"):
            kind = "recipes" if "recipes" in oid else "ingredients"
            if oid.endswith(("_put", "_delete")):
                identifier = params["recipe_id" if kind == "recipes" else "ingredient_id"]
                collection = self.catalog.recipes if kind == "recipes" else self.catalog.ingredients
                if identifier not in collection:
                    raise APIError(404, "not_found", "Ресурс не найден")
                favorites = set(user["favorites"][kind])
                if oid.endswith("_put"):
                    favorites.add(identifier)
                else:
                    favorites.discard(identifier)
                user["favorites"][kind] = sorted(favorites)
                return {'state_version': user['version']}
            identifiers = sorted(user["favorites"][kind])
            items = [self.catalog.ingredient_body(i, user) if kind == "ingredients" else self.catalog.detail(i, user)[0]["recipe"]
                     for i in identifiers]
            paged, page = self.pagination.paginate(db, uid, user, oid, params, items,
                                                     user.get("_dietary", {}).get("version", "") if kind == "recipes" else "")
            result = {"state_version": user["version"], "items": paged, "page": page}
            if kind == "ingredients":
                result["catalog_version"] = self.catalog.version
            return result
        raise ValueError(f"Unsupported operation: {oid}")
