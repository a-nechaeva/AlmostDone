"""Catalogue repositories: PostgreSQL, JSON files, and supplied in-memory records."""
import copy
import json
from pathlib import Path


class PostgresCatalogRepository:
    def __init__(self, store):
        self.store = store

    def load(self):
        with self.store.transaction() as db:
            return load_catalog(db)


class JsonCatalogRepository:
    def __init__(self, path):
        self.path = Path(path)

    def load(self):
        return json.loads(self.path.read_text(encoding="utf-8"))


class MemoryCatalogRepository:
    def __init__(self, data):
        self.data = copy.deepcopy(data)

    def load(self):
        return copy.deepcopy(self.data)


def load_catalog(db):
    db.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
    ingredients = {}
    for row in db.execute("SELECT * FROM ingredients ORDER BY id"):
        item = dict(row)
        for field in ("package_g", "package_price", "kcal", "protein", "fat", "carbs", "grams_per_piece"):
            item[field] = float(item[field]) if item.get(field) is not None else None
        item["aliases"], item["allergens"] = [], []
        ingredients[item["id"]] = item
    for row in db.execute("SELECT ingredient_id,alias FROM ingredient_aliases ORDER BY ingredient_id,alias"):
        ingredients[row["ingredient_id"]]["aliases"].append(row["alias"])
    for row in db.execute("SELECT ia.ingredient_id,a.code FROM ingredient_allergens ia JOIN allergens a ON a.id=ia.allergen_id ORDER BY ia.ingredient_id,a.code"):
        ingredients[row["ingredient_id"]]["allergens"].append(row["code"])
    recipes = {}
    for row in db.execute("SELECT * FROM recipes WHERE author_id IS NULL ORDER BY id"):
        item = dict(row)
        item["items"], item["steps"], item["step_details"] = [], [], []
        recipes[item["id"]] = item
    for row in db.execute("SELECT * FROM recipe_ingredients ORDER BY recipe_id,ingredient_id"):
        if row["recipe_id"] in recipes:
            recipes[row["recipe_id"]]["items"].append({"code": ingredients[row["ingredient_id"]]["code"],
                "qty_g": float(row["qty_g"]) if row["qty_g"] is not None else None, "is_optional": row["is_optional"]})
    for row in db.execute("SELECT * FROM recipe_steps ORDER BY recipe_id,step_no"):
        if row["recipe_id"] in recipes:
            recipes[row["recipe_id"]]["steps"].append(row["instruction"])
            recipes[row["recipe_id"]]["step_details"].append({"number": row["step_no"], "text": row["instruction"],
                                                           "minutes": row["duration_min"]})
    # Numeric database keys are opaque strings at the API boundary.
    for item in recipes.values():
        item["id"] = str(item["id"])
    return {"source_name": "Каталог PostgreSQL", "ingredients": list(ingredients.values()), "recipes": list(recipes.values())}
