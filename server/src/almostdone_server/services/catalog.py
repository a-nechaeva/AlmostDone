"""Catalogue data and presentation, loaded through a repository and computed through an engine port."""
import copy
import hashlib
import json
import math
import unicodedata
from decimal import Decimal, ROUND_HALF_UP

from ..errors import APIError, invalid
from .ports import CatalogRepository, EngineGateway
from .models import ALLERGENS
from . import partial_catalog


def money(kopecks):
    return {"minor_units": kopecks, "currency": "RUB"} if kopecks is not None else None


def kopecks(rubles):
    return int((Decimal(str(rubles)) * 100).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def unsupported(capability):
    # Use 503 for a missing engine capability: the request may be valid, but
    # this server cannot calculate it. Do not replace engine rules with estimates.
    return APIError(503, "service_unavailable", "Готовое ядро не поддерживает этот расчёт",
                    details=[{"field": capability, "code": "engine_capability_missing",
                              "message": "Расчёт не реализован в engine; сервер не подменяет его своим алгоритмом"}])


class Catalog:
    """Read catalogue records from a repository and coordinate their use."""
    def __init__(self, repository: CatalogRepository, gateway: EngineGateway):
        data = repository.load()
        self.gateway = gateway
        self.data = copy.deepcopy(data)
        self.ingredients = {i["code"]: i for i in data["ingredients"]}
        self.recipes = {str(r["id"]): r for r in data["recipes"]}
        self.version = hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()[:24]
        self.source = {"name": data.get("source_name", "Каталог сервера"), "url": None, "observed_at": None}
        self.demo = data.get("demo", False)
        self.gateway.configure(self.data)

    def require_engine(self):
        self.gateway.require_engine()

    def search(self, query):
        return self.gateway.search(query)

    def ingredient(self, ingredient_id):
        if ingredient_id not in self.ingredients:
            raise invalid("Неизвестный ингредиент", "ingredient_id", "unknown_ingredient")
        return self.ingredients[ingredient_id]

    def allowed_units(self, ingredient_id):
        ingredient = self.ingredient(ingredient_id)
        if "allowed_units" in ingredient:
            return ingredient["allowed_units"]
        units = ["g"]
        for unit, field in (("ml", "grams_per_ml"), ("pcs", "grams_per_piece")):
            factor = ingredient.get(field)
            if factor is not None and math.isfinite(float(factor)) and float(factor) > 0:
                units.append(unit)
        return units

    def validate_quantity(self, ingredient_id, quantity):
        ingredient = self.ingredient(ingredient_id)
        if quantity is not None and quantity["unit"] not in self.allowed_units(ingredient_id):
            raise APIError(409, "unit_conflict", "Единица не поддерживается для этого ингредиента")

    def grams(self, ingredient_id, quantity):
        if quantity is None:
            return None
        ing = self.ingredients[ingredient_id]
        factor = {"g": 1, "pcs": ing.get("grams_per_piece"), "ml": ing.get("grams_per_ml")}[quantity["unit"]]
        return quantity["value"] * factor if factor else None

    def quantity(self, ingredient_id, grams):
        if grams is None:
            return None
        ing = self.ingredients[ingredient_id]
        unit = ing.get("display_unit", "g")
        factor = {"g": 1, "pcs": ing.get("grams_per_piece"), "ml": ing.get("grams_per_ml")}[unit]
        return {"value": round(grams / factor, 6), "unit": unit} if factor else None

    def offer(self, ingredient_id):
        ing = self.ingredients[ingredient_id]
        quantity = self.quantity(ingredient_id, ing.get("package_g"))
        if quantity is None or not 0 < quantity["value"] <= 1_000_000:
            return None
        return {"package_id": ingredient_id + "-default", "quantity": quantity,
                "price": money(kopecks(ing["package_price"])) if ing.get("package_price") is not None else None,
                "source": self.source}

    def allergen_assessment(self, ingredient_ids):
        return {"contains": sorted({a for code in ingredient_ids for a in self.ingredients[code].get("allergens", [])}),
                "completeness": "complete" if all(self.ingredients[code].get("allergen_data_complete", False)
                                                   for code in ingredient_ids) else "incomplete",
                "sources": [self.source]}

    def ingredient_nutrition(self, ingredient_id):
        ingredient = self.ingredient(ingredient_id)
        fields = {'kcal': 'kcal', 'protein_g': 'protein', 'fat_g': 'fat', 'carbs_g': 'carbs'}
        try:
            nutrition = {target: float(ingredient[source]) for target, source in fields.items()}
        except (KeyError, TypeError, ValueError, OverflowError):
            return None
        if any(not math.isfinite(value) or value < 0 for value in nutrition.values()):
            return None
        return nutrition

    def ingredient_body(self, ingredient_id, user):
        ing, offer = self.ingredient(ingredient_id), self.offer(ingredient_id)
        return {"id": ingredient_id, "name": ing["name"],
                "nutrition_per_100g": self.ingredient_nutrition(ingredient_id),
                "allowed_units": self.allowed_units(ingredient_id),
                "is_favorite": ingredient_id in user["favorites"]["ingredients"],
                "allergens": self.allergen_assessment([ingredient_id]), "offers": [offer] if offer else []}

    @staticmethod
    def steps(raw):
        if "step_details" in raw:
            return copy.deepcopy(raw["step_details"])
        return [{"number": n, "text": text, "minutes": None} for n, text in enumerate(raw.get("steps", []), 1)]

    def photo_source(self, recipe_id):
        """Original photo link of a catalogue recipe, or None."""
        raw = self.recipes.get(recipe_id)
        return raw.get("photo_url", raw.get("image_url")) or None if raw else None

    def export(self):
        """The whole catalogue for a client that matches recipes on the device.

        Quantities use each ingredient's display unit, as everywhere else in the API. Basic
        products and optional items are not listed in recipes. Recipes with unknown required
        quantities are not exported for local calculation; they remain available by ID and
        in server recommendations. Unconvertible quantities are left out instead of guessing.
        """
        staples, recipes = self.gateway.export()
        ingredients = []
        for code, ing in sorted(self.ingredients.items(), key=lambda kv: kv[1]["name"]):
            offer = self.offer(code)
            ingredients.append({"id": code, "name": ing["name"], "unit": ing.get("display_unit", "g"),
                                "allergens": sorted(ing.get("allergens", [])),
                                "allergen_data_complete": bool(ing.get("allergen_data_complete", False)),
                                "nutrition_per_100g": self.ingredient_nutrition(code),
                                "offer": {"quantity": offer["quantity"], "price": offer["price"]}
                                if offer and offer["price"] else None})
        items = []
        for recipe, metrics in recipes:
            listed = [{"ingredient_id": i.code, "quantity": self.quantity(i.code, i.qty_g)}
                      for i in recipe.required_items if i.code not in staples and i.qty_g]
            if not listed or any(item["quantity"] is None or item["quantity"]["value"] <= 0 for item in listed):
                continue
            items.append({
                "id": recipe.id, "title": recipe.title, "photo_url": self.photo_source(recipe.id),
                "servings": recipe.servings, "minutes": max(1, metrics.cook_time_min),
                "steps": list(recipe.steps), "ingredients": listed,
                "nutrition_per_serving": {"kcal": metrics.kcal, "protein_g": metrics.protein,
                                          "fat_g": metrics.fat, "carbs_g": metrics.carbs},
                "allergens": sorted(metrics.allergens),
                "allergen_data_complete": self.allergen_assessment(
                    [i.code for i in recipe.required_items])["completeness"] == "complete",
                "methods": list(recipe.methods)})
        return {"catalog_version": self.version, "ingredients": ingredients, "recipes": items}

    def prepare(self, user, extra_allergens=()):
        # Request-wide prerequisites only: incomplete per-recipe records must
        # never turn a partially supported catalogue into a global 503.
        self.require_engine()
        prefs = user["preferences"]
        selected = ([prefs["food_type"]] if prefs["food_type"] != "any" else [])
        selected += [key for key in ("gluten_free", "lactose_free", "diabetes") if prefs[key]]
        if prefs["diet_table_id"]:
            selected.append(prefs["diet_table_id"])
        supported = user.get('_dietary', {}).get('supported', ())
        if any(key not in supported for key in selected):
            raise unsupported("dietary_restrictions")
        banned = set(prefs["excluded_allergens"]) | set(extra_allergens)
        stock = {}
        for code, quantity in user["pantry"].items():
            stock[code] = self.grams(code, quantity)
            if quantity is not None and stock[code] is None:
                # A known amount without a conversion factor is not unlimited
                # stock. Return 503 instead of passing it to the engine as None.
                raise unsupported("pantry_unit_conversion:" + code)
        return stock, banned

    def can_calculate(self, recipe_id, servings):
        raw = self.recipes[recipe_id]
        return (recipe_id not in self.gateway.unsupported_recipes
                and all(self.quantity(item["code"], self.ingredients[item["code"]].get("package_g")) is not None
                        for item in raw["items"] if not item.get("is_optional")))

    def detail(self, recipe_id, user, servings=None, extra_allergens=()):
        if recipe_id not in self.recipes:
            raise APIError(404, "not_found", "Рецепт не найден")
        servings = 2 if servings is None else servings
        stock, banned = self.prepare(user, extra_allergens)
        if not self.can_calculate(recipe_id, servings):
            # An API-valid record need not satisfy the engine's stricter model.
            # Preserve it with nullable metrics instead of rejecting the request.
            return partial_catalog.present(self, recipe_id, user, servings, banned), None
        option, visible = self.gateway.detail(recipe_id, stock, banned, servings)
        return self.present(option, user, visible, banned), option

    def present(self, option, user, visible=True, banned=()):
        recipe, metrics, missing = option.recipe, option.metrics, option.missing_g
        raw = self.recipes[recipe.id]
        factor = option.portions / recipe.servings
        ingredients = [{"ingredient_id": item["code"], "name": self.ingredients[item["code"]]["name"],
                        "required": self.quantity(item["code"], item["qty_g"] * factor) if item.get("qty_g") is not None else None, "available": user["pantry"].get(item["code"]),
                        "shortage": self.quantity(item["code"], missing.get(item["code"], 0)) if item.get("qty_g") is not None else None,
                        "availability": "optional" if item.get("is_optional") else "missing" if item["code"] in missing else "enough",
                        "optional": item.get("is_optional", False), "original_amount": item.get("original_amount"), "offer": self.offer(item["code"])}
                       for item in raw["items"]]
        card = {"id": recipe.id, "title": recipe.title, "photo_url": raw.get("photo_url", raw.get("image_url")),
                "servings": option.portions, "minutes": metrics.cook_time_min,
                "nutrition_per_serving": {"kcal": metrics.kcal, "protein_g": metrics.protein,
                                          "fat_g": metrics.fat, "carbs_g": metrics.carbs},
                "nutrition_source": self.source, "buy_cost": money(kopecks(metrics.buy_cost)),
                "availability": {"status": "missing" if option.level else "ready", "missing_count": option.level,
                                 "unknown_quantity_ids": sorted(item.code for item in recipe.required_items
                                                                if item.code in user["pantry"] and user["pantry"][item.code] is None)},
                "suitability": partial_catalog.suitability(self, raw, banned, user.get("_dietary")),
                "allergens": self.allergen_assessment([item["code"] for item in raw["items"]]),
                "is_favorite": recipe.id in user["favorites"]["recipes"],
                "methods": ["no_cook"] if raw.get("no_cook") else sorted(recipe.equipment)}
        return {"state_version": user["version"], "catalog_version": self.version, "recipe": card,
                "ingredients": ingredients, "steps": self.steps(raw),
                "shopping_items": [self.shopping_item(code, *self.gateway.shopping_requirement(code, grams)) for code, grams in sorted(missing.items())]}

    def shopping_item(self, ingredient_id, count, cost):
        return {"key": ingredient_id + ":" + ingredient_id + "-default", "ingredient_id": ingredient_id,
                "package_id": ingredient_id + "-default", "name": self.ingredients[ingredient_id]["name"],
                "package_quantity": self.offer(ingredient_id)["quantity"], "package_count": count,
                "total_price": money(kopecks(cost))}

    def matches(self, user, filters, servings=2):
        def normalize_title(value):
            return " ".join(unicodedata.normalize("NFKC", value).casefold().replace("ё", "е").split())
        query = normalize_title(filters["q"])
        selected = {recipe_id for recipe_id, recipe in self.recipes.items()
                    if query in normalize_title(recipe["title"])}
        stock, banned = self.prepare(user, filters["exclude_allergens"])
        calculable = {recipe_id for recipe_id in selected if self.can_calculate(recipe_id, servings)}
        arguments = {"max_missing": 0 if filters["mode"] == "now" else 3 if filters["mode"] == "buy_1_3" else len(self.ingredients),
                     "max_minutes": filters["max_minutes"], "max_kcal": filters["max_kcal_per_serving"],
                     "equipment": set(filters["equipment"]) - {"no_cook"},
                     "hidden": set(self.recipes) - calculable, "servings": servings}
        dietary_hidden = {rid for rid, item in user.get('_dietary', {}).get('recipes', {}).items() if item['hidden']}
        options, visible_ids = self.gateway.reachable(stock, banned, arguments, dietary_hidden)
        result = [(self.present(option, user, option.recipe.id in visible_ids, banned), option) for option in options
                  if filters["mode"] != "buy_1_3" or option.level > 0]
        for recipe_id in selected - calculable:
            detail = partial_catalog.present(self, recipe_id, user, servings, banned)
            if partial_catalog.matches_filters(detail, filters):
                result.append((detail, None))
        return sorted(result, key=partial_catalog.order)

    def graph(self, details, options):
        self.require_engine()
        from .presentation import graph
        return graph(self, details, options)

    def purchases(self, user, body, single):
        matches = self.matches(user, body["filters"], body["servings"])
        options = [option for detail, option in matches if option is not None and detail["recipe"]["suitability"]["status"] == "allowed"]
        unpriced = sorted(detail["recipe"]["id"] for detail, option in matches if option is None
                          and detail["recipe"]["suitability"]["status"] == "allowed")
        if not single:
            plan = self.gateway.budget_purchases(options, body["budget"]["minor_units"])
            items = [self.shopping_item(code, count, count * self.ingredients[code]["package_price"])
                     for code, count in sorted(plan.items.items())]
            return {"request_id": body["request_id"], "state_version": user["version"],
                    "catalog_version": self.version, "servings": body["servings"],
                    "unpriced_recipe_ids": unpriced, "semantics": "alternatives",
                    "shopping_items": items, "unlocked_recipe_ids": list(plan.unlocked),
                    "total_cost": money(kopecks(plan.total_cost)) if items else None,
                    "status": "found" if items else "insufficient_data" if unpriced else "no_plan"}
        budget = body["budget"]["minor_units"]
        # Filter individual recipes before the engine groups them by ingredient:
        # an expensive recipe must not inflate an otherwise affordable purchase.
        affordable = [option for option in options if option.level == 1
                      and all(kopecks(self.gateway.shopping_requirement(code, grams)[1]) <= budget
                              for code, grams in option.missing_g.items())]
        suggestions = self.gateway.single_purchases(affordable)
        return {"request_id": body["request_id"], "state_version": user["version"], "catalog_version": self.version,
                "servings": body["servings"], "unpriced_recipe_ids": unpriced, "semantics": "alternatives",
                "options": [{"shopping_item": self.shopping_item(s.code, s.packs, s.price),
                             "unlocked_recipe_ids": list(s.unlocks)} for s in suggestions],
                "status": "found" if suggestions else "insufficient_data" if unpriced else "no_plan"}


class CatalogService:
    def __init__(self, catalog, pagination, dietary=None):
        self.catalog, self.pagination, self.dietary = catalog, pagination, dietary

    def execute(self, db, uid, user, session, oid, body, params):
        if oid in ("catalog_allergens", "catalog_dietary_options"):
            items = ([{"id": key, "name": value, "support": "supported"} for key, value in ALLERGENS.items()]
                     if oid == "catalog_allergens" else
                     [{"id": value, "name": label, "support": "supported" if value == "any" else "unsupported",
                       "profile_binding": {"field": "food_type", "value": value}}
                      for value, label in (("any", "Без предпочтений"), ("vegetarian", "Вегетарианство"), ("vegan", "Веганство"))]
                     + [{"id": field, "name": label, "support": "unsupported",
                         "profile_binding": {"field": field, "value": True}}
                        for field, label in (("gluten_free", "Без глютена"), ("lactose_free", "Без лактозы"), ("diabetes", "Диабет"))]
                     + [{"id": f"pevzner_{i}", "name": f"Стол {i}", "support": "unsupported",
                         "profile_binding": {"field": "diet_table_id", "value": f"pevzner_{i}"}} for i in range(1, 16)])
            if oid == 'catalog_dietary_options':
                supported = self.dietary.supported(db) if self.dietary else {'any'}
                for item in items:
                    item['support'] = 'supported' if item['id'] in supported else 'unsupported'
            return {'catalog_version': self.catalog.version, 'items': items}
        if oid == "catalog_search":
            q = params["q"].casefold().strip().replace("ё", "е")
            items = [self.catalog.ingredient_body(i, user) for i in self.catalog.search(q)]
            paged, page = self.pagination.paginate(db, uid, user, oid, params, items, q)
            return {'state_version': user['version'], 'catalog_version': self.catalog.version, 'items': paged, 'page': page}
        if oid == "catalog_export":
            return self.catalog.export()
        if oid == "recipes_get":
            excluded = params.get("exclude_allergens", [])
            if set(excluded) - set(ALLERGENS):
                raise invalid("Неизвестный аллерген", "exclude_allergens")
            return self.catalog.detail(params['recipe_id'], user, params.get('servings'), excluded)[0]
        raise ValueError(f"Unsupported operation: {oid}")
