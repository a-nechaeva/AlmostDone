import pytest

from dishgraph import catalog_from_dict


def ing(code, price, pack, kcal=0, protein=0, fat=0, carbs=0, allergens=(), staple=False):
    return {
        "code": code, "name": code.capitalize(), "package_g": pack, "package_price": price,
        "kcal": kcal, "protein": protein, "fat": fat, "carbs": carbs,
        "allergens": list(allergens), "is_staple": staple,
    }


def recipe(id, minutes, servings, *items, equipment=()):
    return {
        "id": id, "title": id, "cook_time_min": minutes, "servings": servings,
        "needs_microwave": "microwave" in equipment,
        "needs_stove": "stove" in equipment,
        "needs_oven": "oven" in equipment,
        "items": [
            {"code": c, "qty_g": g, **({"is_optional": True} if opt else {})}
            for c, g, *rest in items
            for opt in [bool(rest and rest[0])]
        ],
    }


SMALL = {
    "ingredients": [
        ing("salt", 20, 1000, staple=True),
        ing("egg", 100, 500, kcal=150, protein=10, fat=10, carbs=1, allergens=["eggs"]),
        ing("milk", 80, 1000, kcal=50, protein=3, fat=2.5, carbs=5, allergens=["milk"]),
        ing("flour", 60, 1000, kcal=300, protein=10, fat=1, carbs=70, allergens=["gluten"]),
        ing("cheese", 200, 200, kcal=350, allergens=["milk"]),
        ing("ham", 300, 300, kcal=250),
        ing("herb", 50, 50, kcal=40),
    ],
    "recipes": [
        recipe("omelette", 10, 2, ("egg", 100), ("milk", 100), ("salt", 2), equipment=["stove"]),
        recipe("milk_drink", 2, 1, ("milk", 200), equipment=["microwave"]),
        recipe("herb_egg", 5, 1, ("egg", 100), ("herb", 5, True)),
        recipe("pancakes", 30, 2, ("egg", 50), ("milk", 200), ("flour", 100), equipment=["stove"]),
        recipe("cheese_pancakes", 40, 2, ("egg", 50), ("milk", 200), ("flour", 100), ("cheese", 50),
               equipment=["stove", "oven"]),
        recipe("big", 60, 1, ("egg", 50), ("milk", 50), ("flour", 50), ("cheese", 50), ("ham", 50),
               equipment=["stove"]),
    ],
}

ALL_CODES = {i["code"] for i in SMALL["ingredients"]}


@pytest.fixture
def catalog():
    return catalog_from_dict(SMALL)
