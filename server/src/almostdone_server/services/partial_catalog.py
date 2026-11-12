"""Present catalogue records the engine cannot calculate, without estimates."""


def methods(raw):
    if raw.get("no_cook"):
        return ["no_cook"]
    return sorted(method for method in ("stove", "oven", "microwave") if raw.get("needs_" + method))


def suitability(catalog, raw, banned, dietary=None):
    reasons, hidden, incomplete = [], False, []
    for item in raw["items"]:
        code = item["code"]
        ingredient = catalog.ingredients[code]
        excluded = sorted(set(ingredient.get("allergens", [])) & set(banned))
        optional = item.get("is_optional", False)
        if excluded:
            reasons.append({"code": "skip_optional" if optional else "excluded_allergen",
                            "message": "Исключите необязательный ингредиент" if optional else "Содержит исключённый аллерген",
                            "ingredient_ids": [code], "restriction_ids": excluded})
            hidden |= not optional
        if banned and not optional and not ingredient.get("allergen_data_complete", False):
            incomplete.append(code)
    if incomplete:
        reasons.append({"code": "incomplete_allergen_data", "message": "Сведения об аллергенах неполные",
                        "ingredient_ids": sorted(set(incomplete)), "restriction_ids": sorted(banned)})
    if dietary and dietary.get('database'):
        decision = dietary['recipes'].get(str(raw['id']))
        if decision is None:
            incomplete.append('dietary')
            reasons.append({'code': 'dietary_data_unavailable', 'message': 'Dietary assessment is unavailable',
                            'ingredient_ids': [], 'restriction_ids': []})
        else:
            hidden |= decision['hidden']
            if decision.get('diet_violation', bool(decision['restrictions'])):
                reasons.append({'code': 'excluded_diet', 'message': 'Recipe does not satisfy the configured diet rules',
                                'ingredient_ids': [], 'restriction_ids': decision['restrictions']})
            optional_ids = sorted(set(decision['skip_optional']) - {
                code for reason in reasons if reason['code'] == 'skip_optional' for code in reason['ingredient_ids']
            })
            if optional_ids:
                reasons.append({'code': 'skip_optional', 'message': 'Omit optional ingredients excluded by your profile',
                                'ingredient_ids': optional_ids, 'restriction_ids': []})
    return {"status": "hidden" if hidden else "unknown" if incomplete else "allowed", "reasons": reasons}


def present(catalog, recipe_id, user, servings, banned):
    raw = catalog.recipes[recipe_id]
    native_servings = servings == raw["servings"]
    ingredients = []
    for item in raw["items"]:
        code = item["code"]
        required = catalog.quantity(code, item.get("qty_g")) if native_servings else None
        optional = item.get("is_optional", False)
        # Unknown stock is sufficient only when the recipe requirement is known.
        unlimited = required is not None and code in user["pantry"] and user["pantry"][code] is None
        ingredients.append({"ingredient_id": code, "name": catalog.ingredients[code]["name"],
                            "required": required, "available": user["pantry"].get(code),
                            "shortage": catalog.quantity(code, 0) if unlimited else None,
                            "availability": "optional" if optional else "enough" if unlimited else "unknown",
                            "optional": optional, "original_amount": item.get("original_amount"), "offer": catalog.offer(code)})
    minutes = raw.get("cook_time_min")
    card = {"id": recipe_id, "title": raw["title"], "photo_url": raw.get("photo_url", raw.get("image_url")),
            "servings": servings, "minutes": minutes if isinstance(minutes, int) and minutes > 0 else None,
            "nutrition_per_serving": None, "nutrition_source": None, "buy_cost": None,
            "availability": {"status": "unknown", "missing_count": 0,
                             "unknown_quantity_ids": sorted({item["code"] for item in raw["items"]
                                 if not item.get("is_optional") and item["code"] in user["pantry"] and user["pantry"][item["code"]] is None})},
            "suitability": suitability(catalog, raw, banned, user.get("_dietary")),
            "allergens": catalog.allergen_assessment([item["code"] for item in raw["items"]]),
            "is_favorite": recipe_id in user["favorites"]["recipes"], "methods": methods(raw)}
    return {"state_version": user["version"], "catalog_version": catalog.version, "recipe": card,
            "ingredients": ingredients, "steps": catalog.steps(raw), "shopping_items": []}


def matches_filters(detail, filters):
    # Only confirmed metadata may satisfy a filter. Availability-dependent
    # modes cannot include a recipe for which no engine calculation exists.
    if filters["mode"] != "all":
        return False
    card = detail["recipe"]
    if filters["max_minutes"] is not None and (card["minutes"] is None or card["minutes"] > filters["max_minutes"]):
        return False
    if filters["max_kcal_per_serving"] is not None:
        return False
    required = set(card["methods"])
    if required == {"no_cook"}:
        return True
    if not required:
        required = {"stove", "oven", "microwave"}
    return required <= set(filters["equipment"])


def order(match):
    card = match[0]["recipe"]
    price = card["buy_cost"]
    return ({"ready": 0, "missing": 1, "unknown": 2}[card["availability"]["status"]],
            card["availability"]["missing_count"], price is None,
            price["minor_units"] if price is not None else 0, card["id"])
