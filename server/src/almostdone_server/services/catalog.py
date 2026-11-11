"""Catalogue data and presentation, loaded through a repository and computed through an engine port."""
import copy
import hashlib
import json
from decimal import Decimal, ROUND_HALF_UP

from ..errors import APIError, invalid
from .ports import CatalogRepository, EngineGateway
from .models import ALLERGENS


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

    def validate_quantity(self, ingredient_id, quantity):
        ingredient = self.ingredient(ingredient_id)
        if quantity is not None and quantity["unit"] not in ingredient.get("allowed_units", [ingredient.get("display_unit", "g")]):
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

    def ingredient_body(self, ingredient_id, user):
        ing, offer = self.ingredient(ingredient_id), self.offer(ingredient_id)
        return {"id": ingredient_id, "name": ing["name"],
                "allowed_units": ing.get("allowed_units", [ing.get("display_unit", "g")]),
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
        products, optional items and items without an amount are not listed in recipes: the
        engine does not count them as something to buy either. A recipe whose amounts cannot be
        converted to display units is left out instead of guessing.
        """
        staples, recipes = self.gateway.export()
        ingredients = []
        for code, ing in sorted(self.ingredients.items(), key=lambda kv: kv[1]["name"]):
            offer = self.offer(code)
            ingredients.append({"id": code, "name": ing["name"], "unit": ing.get("display_unit", "g"),
                                "allergens": sorted(ing.get("allergens", [])),
                                "allergen_data_complete": bool(ing.get("allergen_data_complete", False)),
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

    def prepare(self, user, recipe_ids, servings, extra_allergens=()):
        self.require_engine()
        prefs = user["preferences"]
        if prefs["food_type"] != "any" or any(prefs[key] for key in ("gluten_free", "lactose_free", "diabetes", "diet_table_id")):
            # The engine cannot verify these restrictions; 503 avoids claiming
            # that an unverified recipe satisfies the user's dietary profile.
            raise unsupported("dietary_restrictions")
        banned = set(prefs["excluded_allergens"]) | set(extra_allergens)
        for recipe_id in recipe_ids:
            if recipe_id in self.gateway.unsupported_recipes:
                # The engine rejected this recipe's data. Return 503 rather
                # than inventing missing values or changing its validation rules.
                raise unsupported("recipe_data:" + recipe_id)
            raw = self.recipes[recipe_id]
            if servings is not None and servings != raw["servings"]:
                # The engine calculates only the recipe's original servings.
                # Return 503 until scaling is implemented in engine/.
                raise unsupported("serving_scaling")
            if any(self.quantity(item["code"], self.ingredients[item["code"]]["package_g"]) is None for item in raw["items"]):
                # Required unit conversions are unavailable; 503 prevents
                # presenting guessed ingredient or package quantities.
                raise unsupported("recipe_unit_conversion:" + recipe_id)
            if banned and any(not self.ingredients[item["code"]].get("allergen_data_complete", False) for item in raw["items"]):
                # The engine cannot assess incomplete allergen data. Return
                # 503 instead of treating unknown allergens as safe.
                raise unsupported("incomplete_allergen_data")
            if banned and any(item.get("is_optional") and banned.intersection(self.ingredients[item["code"]].get("allergens", []))
                              for item in raw["items"]):
                # Optional-allergen warnings are not supported by the engine;
                # 503 avoids silently dropping the warning or hiding the dish.
                raise unsupported("optional_allergen_warnings")
        stock = {}
        for code, quantity in user["pantry"].items():
            stock[code] = self.grams(code, quantity)
            if quantity is not None and stock[code] is None:
                # A known amount without a conversion factor is not unlimited
                # stock. Return 503 instead of passing it to the engine as None.
                raise unsupported("pantry_unit_conversion:" + code)
        return stock, banned

    def detail(self, recipe_id, user, servings=None, extra_allergens=()):
        if recipe_id not in self.recipes:
            raise APIError(404, "not_found", "Рецепт не найден")
        servings = 2 if servings is None else servings
        stock, banned = self.prepare(user, [recipe_id], servings, extra_allergens)
        option, visible = self.gateway.detail(recipe_id, stock, banned)
        return self.present(option, user, visible, banned), option

    def present(self, option, user, visible=True, banned=()):
        recipe, metrics, missing = option.recipe, option.metrics, option.missing_g
        raw = self.recipes[recipe.id]
        # The engine already decided visibility. Only format its allergen
        # sources for the REST response; do not introduce new filtering rules.
        excluded = sorted(set(metrics.allergens).intersection(banned))
        reasons = [{"code": "excluded_allergen", "message": "Содержит исключённый аллерген",
                    "ingredient_ids": sorted({code for allergen in excluded for code in metrics.allergens[allergen]}),
                    "restriction_ids": excluded}] if not visible and excluded else []
        ingredients = [{"ingredient_id": item.code, "name": self.ingredients[item.code]["name"],
                        "required": self.quantity(item.code, item.qty_g), "available": user["pantry"].get(item.code),
                        "shortage": self.quantity(item.code, missing.get(item.code, 0)),
                        "availability": "optional" if item.is_optional else "missing" if item.code in missing else "enough",
                        "optional": item.is_optional, "original_amount": None, "offer": self.offer(item.code)}
                       for item in recipe.items]
        card = {"id": recipe.id, "title": recipe.title, "photo_url": raw.get("photo_url", raw.get("image_url")),
                "servings": recipe.servings, "minutes": metrics.cook_time_min,
                "nutrition_per_serving": {"kcal": metrics.kcal, "protein_g": metrics.protein,
                                          "fat_g": metrics.fat, "carbs_g": metrics.carbs},
                "nutrition_source": self.source, "buy_cost": money(kopecks(metrics.buy_cost)),
                "availability": {"status": "missing" if option.level else "ready", "missing_count": option.level,
                                 "unknown_quantity_ids": sorted(item.code for item in recipe.required_items
                                                                if item.code in user["pantry"] and user["pantry"][item.code] is None)},
                "suitability": {"status": "allowed" if visible else "hidden", "reasons": reasons},
                "allergens": self.allergen_assessment([item.code for item in recipe.required_items]),
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
        if filters["q"].strip():
            # The engine has ingredient search, but no recipe-title filter.
            # Return 503 rather than ignoring a valid search constraint.
            raise unsupported("recipe_title_search")
        stock, banned = self.prepare(user, self.recipes, servings, filters["exclude_allergens"])
        arguments = {"max_missing": 0 if filters["mode"] == "now" else 3 if filters["mode"] == "buy_1_3" else len(self.ingredients),
                     "max_minutes": filters["max_minutes"], "max_kcal": filters["max_kcal_per_serving"],
                     "equipment": set(filters["equipment"]) - {"no_cook"}}
        options, visible_ids = self.gateway.reachable(stock, banned, arguments)
        return [(self.present(option, user, option.recipe.id in visible_ids, banned), option) for option in options
                if filters["mode"] != "buy_1_3" or option.level > 0]

    def graph(self, details, options):
        self.require_engine()
        from .presentation import graph
        return graph(self, details, options)

    def purchases(self, user, body, single):
        if not single:
            # The engine exposes a greedy plan, while the API promises an exact
            # maximum. Return 503 until the engine implements that guarantee.
            raise unsupported("exact_budget_optimization")
        matches = self.matches(user, body["filters"], body["servings"])
        options = [option for detail, option in matches if detail["recipe"]["suitability"]["status"] == "allowed"]
        suggestions = self.gateway.single_purchases(options)
        budget = body["budget"]["minor_units"]
        if any(kopecks(suggestion.price) > budget for suggestion in suggestions):
            # The engine does not optimize single purchases under a budget.
            # Return 503 rather than claiming its unconstrained result is valid.
            raise unsupported("budget_constrained_single_purchase")
        return {"request_id": body["request_id"], "state_version": user["version"], "catalog_version": self.version,
                "servings": body["servings"], "unpriced_recipe_ids": [], "semantics": "alternatives",
                "options": [{"shopping_item": self.shopping_item(s.code, s.packs, s.price),
                             "unlocked_recipe_ids": list(s.unlocks)} for s in suggestions],
                "status": "found" if suggestions else "no_plan"}


class CatalogService:
    def __init__(self, catalog, pagination):
        self.catalog, self.pagination = catalog, pagination

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
