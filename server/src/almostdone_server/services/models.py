"""Application state independent of HTTP and database implementations."""
def default_user():
    return {"version": 0, "pantry": {}, "favorites": {"recipes": [], "ingredients": []},
            "preferences": {"food_type": "any", "excluded_allergens": [], "gluten_free": False,
                            "lactose_free": False, "diabetes": False, "diet_table_id": None}}


ALLERGENS = {
    "gluten": "Глютен", "milk": "Молочный белок", "eggs": "Яйца", "fish": "Рыба",
    "crustaceans": "Ракообразные", "molluscs": "Моллюски", "peanuts": "Арахис",
    "nuts": "Орехи", "soy": "Соя", "sesame": "Кунжут", "mustard": "Горчица",
    "celery": "Сельдерей", "lupin": "Люпин", "sulphites": "Сульфиты",
}
