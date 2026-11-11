"""Translate catalogue records to dishgraph models and delegate calculations."""
import importlib
from dataclasses import asdict
from types import SimpleNamespace

from ..errors import APIError
from ..services.catalog import unsupported


class DishgraphGateway:
    def configure(self, data):
        self.ingredients = {item["code"]: item for item in data["ingredients"]}
        self.recipes = {str(item["id"]): item for item in data["recipes"]}
        self.engine_catalog, self.lookup_catalog, self.search_index = None, None, None
        self.unsupported_recipes = set()
        try:
            self.engine = importlib.import_module("dishgraph")
        except ModuleNotFoundError as error:
            if error.name != "dishgraph":
                raise
            self.engine = None
            return
        # Search/recognition need raw names and aliases, not substitute prices or nutrients.
        self.lookup_catalog = self.engine.Catalog(
            ingredients={code: SimpleNamespace(**{"aliases": (), "is_staple": False, **raw})
                         for code, raw in self.ingredients.items()}, recipes=())
        self.search_index = self.engine.SearchIndex(self.lookup_catalog)
        valid_ingredients = {}
        for code, raw in self.ingredients.items():
            try:
                loaded = self.engine.catalog_from_dict({"ingredients": [raw], "recipes": []})
                valid_ingredients[code] = loaded.ingredients[code]
            except (TypeError, ValueError, KeyError):
                pass
        loaded_recipes = []
        for recipe_id, raw in self.recipes.items():
            try:
                if raw.get("no_cook") and any(raw.get("needs_" + method) for method in self.engine.EQUIPMENT):
                    raise ValueError("Contradictory no_cook is not supported by the engine model")
                # The API permits unknown quantities for optional ingredients.
                # Engine calculations use required_items only, so project that
                # same required-only composition into its strict input model.
                # Preserve all original optional rows for API presentation.
                required = [item for item in raw["items"] if not item.get("is_optional")]
                loaded = self.engine.catalog_from_dict({"ingredients": [self.ingredients[item["code"]] for item in required],
                                                        "recipes": [{**raw, "items": required}]})
                loaded_recipes.append(loaded.recipes[0])
            except (TypeError, ValueError, KeyError):
                self.unsupported_recipes.add(recipe_id)
        self.engine_catalog = self.engine.Catalog(valid_ingredients, tuple(loaded_recipes))

    def require_engine(self):
        if self.engine is None:
            raise APIError(503, "service_unavailable", "Движок dishgraph не установлен")

    def search(self, query):
        self.require_engine()
        from dishgraph.search import MAX_QUERY_LEN
        if len(query.strip()) > MAX_QUERY_LEN:
            # The API accepts longer queries than the engine's search limit;
            # 503 reports that capability gap without truncating the query.
            raise unsupported("ingredient_search_query_length")
        return [hit.code for hit in self.search_index.search(query, limit=len(self.ingredients))]

    def detail(self, recipe_id, stock, banned):
        recipe = self.engine_catalog.recipe(recipe_id)
        option = self.engine.dish_option(recipe, stock, self.engine_catalog)
        single_catalog = self.engine.Catalog(self.engine_catalog.ingredients, (recipe,))
        visible = self.engine.reachable_dishes(stock, single_catalog,
                                              max_missing=len(self.ingredients), exclude_allergens=banned)
        return option, bool(visible)

    def reachable(self, stock, banned, arguments):
        options = self.engine.reachable_dishes(stock, self.engine_catalog, **arguments)
        allowed = (self.engine.reachable_dishes(stock, self.engine_catalog, exclude_allergens=banned, **arguments)
                   if banned else options)
        return options, {option.recipe.id for option in allowed}

    def shopping_requirement(self, code, grams):
        return self.engine_catalog.packs_needed(code, grams), self.engine_catalog.pack_cost(code, grams)

    def build_graph(self, options):
        self.require_engine()
        return self.engine.build_graph(options, self.engine_catalog)

    def serialize_option(self, option):
        return {"recipe_id": option.recipe.id, "missing_g": dict(option.missing_g),
                "metrics": asdict(option.metrics)}

    def restore_option(self, value):
        return self.engine.DishOption(recipe=self.engine_catalog.recipe(value["recipe_id"]),
                                      missing_g=value["missing_g"],
                                      metrics=self.engine.DishMetrics(**value["metrics"]))

    def single_purchases(self, options):
        return self.engine.best_single_purchases(options, self.engine_catalog)
