"""Catalogue repositories: PostgreSQL, JSON files, and supplied in-memory records."""
import copy
import json
import re
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


class SeedCatalogRepository:
    """The same records as PostgresCatalogRepository, read from a pg_dump file (db/seed.sql).

    For a laptop demo without PostgreSQL: the dump is the database, so the catalogue matches.
    """
    def __init__(self, path):
        self.path = Path(path)

    def load(self):
        return load_catalog(SeedDump(self.path))


class SeedDump:
    """Answer the SELECTs of load_catalog() from the COPY blocks of a pg_dump file."""
    COPY = re.compile(r"COPY public\.(\w+) \(([^)]*)\) FROM stdin;")
    ESCAPES = {"\\n": "\n", "\\t": "\t", "\\r": "\r", "\\\\": "\\"}
    INTEGERS = {"id", "servings", "cook_time_min", "recipe_id", "ingredient_id", "allergen_id", "step_no",
                "duration_min", "author_id"}
    BOOLEANS = {"is_staple", "needs_microwave", "needs_stove", "needs_oven", "no_cook", "is_optional"}

    def __init__(self, path):
        self.tables, current, columns = {}, None, []
        for line in Path(path).read_text(encoding="utf-8").split("\n"):
            if current is None:
                match = self.COPY.match(line)
                if match:
                    current, columns = match[1], [c.strip() for c in match[2].split(",")]
                    self.tables[current] = []
            elif line == "\\.":
                current = None
            else:
                self.tables[current].append({c: self.value(c, v) for c, v in zip(columns, line.split("\t"))})

    def value(self, column, text):
        if text == "\\N":
            return None
        text = re.sub(r"\\[ntr\\]", lambda m: self.ESCAPES[m[0]], text)
        if column in self.INTEGERS:
            return int(text)
        if column in self.BOOLEANS:
            return text == "t"
        return text

    def execute(self, sql):
        if sql.startswith("SET "):
            return []
        t = self.tables
        if sql.startswith("SELECT * FROM ingredients"):
            return sorted(t["ingredients"], key=lambda r: r["id"])
        if sql.startswith("SELECT ingredient_id,alias"):
            return sorted(t.get("ingredient_aliases", []), key=lambda r: (r["ingredient_id"], r["alias"]))
        if sql.startswith("SELECT ia.ingredient_id,a.code"):
            codes = {r["id"]: r["code"] for r in t.get("allergens", [])}
            rows = [{"ingredient_id": r["ingredient_id"], "code": codes[r["allergen_id"]]}
                    for r in t.get("ingredient_allergens", [])]
            return sorted(rows, key=lambda r: (r["ingredient_id"], r["code"]))
        if sql.startswith("SELECT * FROM recipes WHERE author_id IS NULL"):
            return sorted((r for r in t["recipes"] if r.get("author_id") is None), key=lambda r: r["id"])
        if sql.startswith("SELECT * FROM recipe_ingredients"):
            return sorted(t["recipe_ingredients"], key=lambda r: (r["recipe_id"], r["ingredient_id"]))
        if sql.startswith("SELECT * FROM recipe_steps"):
            return sorted(t.get("recipe_steps", []), key=lambda r: (r["recipe_id"], r["step_no"]))
        raise ValueError("Unsupported catalogue query: " + sql)


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
