import pytest

from dishgraph import dish_metrics, dish_option, missing, missing_grams, reachable_dishes

from .conftest import ALL_CODES


def levels(options):
    return {o.recipe.id: o.level for o in options}


def test_missing_ignores_staples_and_optional(catalog):
    assert missing(catalog.recipe("omelette"), set(), catalog.staples) == {"egg", "milk"}
    assert missing(catalog.recipe("herb_egg"), {"egg"}, catalog.staples) == frozenset()


def test_empty_pantry(catalog):
    assert levels(reachable_dishes(set(), catalog)) == {
        "milk_drink": 1,
        "herb_egg": 1,
        "omelette": 2,
        "pancakes": 3,
        # cheese_pancakes (4) и big (5) не помещаются в max_missing=3
    }


def test_full_pantry_everything_level_zero(catalog):
    options = reachable_dishes(ALL_CODES, catalog)
    assert len(options) == len(catalog.recipes)
    assert all(o.level == 0 for o in options)


def test_max_missing(catalog):
    assert set(levels(reachable_dishes(set(), catalog, max_missing=1))) == {"milk_drink", "herb_egg"}
    assert set(levels(reachable_dishes(set(), catalog, max_missing=0))) == set()
    assert "big" in levels(reachable_dishes(set(), catalog, max_missing=5))


def test_sorted_by_level_then_cost(catalog):
    options = reachable_dishes({"egg"}, catalog)
    keys = [(o.level, o.metrics.buy_cost) for o in options]
    assert keys == sorted(keys)
    assert options[0].recipe.id == "herb_egg"


# --- кладовка с граммами ---------------------------------------------------------------

def test_quantity_unknown_is_enough(catalog):
    assert missing_grams(catalog.recipe("omelette"), {"egg": None, "milk": None}, catalog.staples) == {}


def test_quantity_partial(catalog):
    # омлету нужно 100 г яиц и 100 г молока
    assert missing_grams(catalog.recipe("omelette"), {"egg": 40, "milk": 150}, catalog.staples) == {"egg": 60}


def test_quantity_exactly_enough(catalog):
    assert missing_grams(catalog.recipe("omelette"), {"egg": 100, "milk": 100}, catalog.staples) == {}


def test_set_and_dict_pantry_are_equivalent(catalog):
    a = levels(reachable_dishes({"egg", "milk"}, catalog))
    b = levels(reachable_dishes({"egg": None, "milk": None}, catalog))
    assert a == b


def test_partial_quantity_changes_level(catalog):
    # молока 150 г: на омлет (100 г) хватает, на молочный напиток (200 г) — нет
    lv = levels(reachable_dishes({"egg": None, "milk": 150}, catalog))
    assert lv["omelette"] == 0
    assert lv["milk_drink"] == 1


# --- упаковки --------------------------------------------------------------------------

def test_packs_rounded_up(catalog):
    assert catalog.packs_needed("ham", 700) == 3  # упаковки по 300 г
    assert catalog.pack_cost("ham", 700) == 900
    assert catalog.packs_needed("egg", 500) == 1
    assert catalog.packs_needed("egg", 500.5) == 2
    assert catalog.packs_needed("egg", 0) == 0


def test_buy_cost_uses_packs(catalog):
    m = dish_metrics(catalog.recipe("big"), {"ham": 700}, catalog)
    assert m.buy_cost == 900


# --- метрики ---------------------------------------------------------------------------

def test_metrics_by_hand(catalog):
    m = dish_metrics(catalog.recipe("omelette"), {"egg": 100, "milk": 100}, catalog)
    assert m.buy_cost == 180  # упаковка яиц 100 + молоко 80
    # (100/500*100 + 100/1000*80 + 2/1000*20) / 2 порции = 28.04 / 2; соль — базовый, но в цене порции есть
    assert m.portion_cost == pytest.approx(14.0)
    assert m.kcal == 100  # (150 + 50) / 2
    assert m.protein == 6.5  # (10 + 3) / 2
    assert m.cook_time_min == 10
    assert m.allergens == {"eggs": ("egg",), "milk": ("milk",)}


def test_optional_ingredient_not_in_metrics(catalog):
    m = dish_metrics(catalog.recipe("herb_egg"), {}, catalog)
    assert m.kcal == 150  # только яйцо, без зелени


def test_allergen_sources_merge(catalog):
    m = dish_metrics(catalog.recipe("cheese_pancakes"), {}, catalog)
    assert m.allergens["milk"] == ("cheese", "milk")


# --- фильтры ---------------------------------------------------------------------------

def test_exclude_allergens(catalog):
    ids = set(levels(reachable_dishes(ALL_CODES, catalog, exclude_allergens={"milk"})))
    assert ids == {"herb_egg"}


def test_max_minutes_and_kcal(catalog):
    assert set(levels(reachable_dishes(ALL_CODES, catalog, max_minutes=5))) == {"milk_drink", "herb_egg"}
    assert set(levels(reachable_dishes(ALL_CODES, catalog, max_kcal=100))) == {"milk_drink", "omelette"}


def test_equipment_filter(catalog):
    only_microwave = set(levels(reachable_dishes(ALL_CODES, catalog, equipment={"microwave"})))
    assert only_microwave == {"milk_drink"}  # herb_egg без сведений о технике — не обещаем
    nothing = set(levels(reachable_dishes(ALL_CODES, catalog, equipment=set())))
    assert nothing == set()
    no_oven = set(levels(reachable_dishes(ALL_CODES, catalog, equipment={"stove", "microwave"})))
    assert "cheese_pancakes" not in no_oven and "pancakes" in no_oven and "herb_egg" not in no_oven
    everything = set(levels(reachable_dishes(ALL_CODES, catalog, equipment={"stove", "oven", "microwave"})))
    assert "herb_egg" in everything  # без сведений — проходит, только если есть вся техника


def test_no_cook_always_fits():
    import copy
    from dishgraph import catalog_from_dict
    from .conftest import SMALL, recipe
    data = copy.deepcopy(SMALL)
    data["recipes"].append({**recipe("salad", 5, 1, ("herb", 50)), "no_cook": True})
    cat = catalog_from_dict(data)
    assert "salad" in levels(reachable_dishes(ALL_CODES, cat, equipment=set()))
    assert cat.recipe("salad").methods == ("no_cook",)
    assert cat.recipe("omelette").methods == ("stove",)
    assert cat.recipe("herb_egg").methods == ()  # нет сведений


def test_no_cook_with_equipment_rejected():
    import copy
    import pytest as _pytest
    from dishgraph import CatalogError, catalog_from_dict
    from .conftest import SMALL
    data = copy.deepcopy(SMALL)
    data["recipes"][0]["no_cook"] = True  # у омлета needs_stove
    with _pytest.raises(CatalogError, match="no_cook"):
        catalog_from_dict(data)


def test_servings_scale_missing(catalog):
    # омлет на 2 порции: 100 г яиц и 100 г молока; на 6 порций — втрое больше
    opt = dish_option(catalog.recipe("omelette"), {"egg": 200, "milk": None}, catalog, servings=6)
    assert opt.missing_g == {"egg": 100.0}  # нужно 300 г, есть 200
    assert opt.metrics.buy_cost == 100  # одна упаковка яиц (500 г)
    assert opt.to_dict(catalog)["servings"] == 6
    assert opt.metrics.kcal == 100  # на порцию не меняется


def test_servings_change_level(catalog):
    lv2 = levels(reachable_dishes({"egg": 200, "milk": None}, catalog))
    lv6 = levels(reachable_dishes({"egg": 200, "milk": None}, catalog, servings=6))
    assert lv2["omelette"] == 0 and lv6["omelette"] == 1


def test_equipment_unknown_rejected(catalog):
    with pytest.raises(ValueError, match="toaster"):
        reachable_dishes(ALL_CODES, catalog, equipment={"toaster"})


def test_hidden_recipes_excluded(catalog):
    ids = set(levels(reachable_dishes(ALL_CODES, catalog, hidden={"omelette", "big"})))
    assert "omelette" not in ids and "big" not in ids and "pancakes" in ids


def test_dish_option_for_hidden_card(catalog):
    opt = dish_option(catalog.recipe("big"), {"egg"}, catalog)
    assert opt.level == 4  # для «Скрытых блюд» лимит уровня не применяется
    assert opt.to_dict(catalog)["id"] == "big"


def test_to_dict(catalog):
    d = reachable_dishes({"egg"}, catalog)[1].to_dict(catalog)
    assert d["id"] == "milk_drink"
    assert d["missing"] == [{"code": "milk", "name": "Milk", "missing_g": 200.0, "packs": 1, "cost": 80.0}]
    assert d["allergens"] == ["milk"]
    assert d["equipment"] == ["microwave"]


# --- граммы в рецепте не указаны (qty_g = NULL в БД) ----------------------------------------

def _with_recipe(*items):
    import copy

    from dishgraph import catalog_from_dict

    from .conftest import SMALL, recipe

    data = copy.deepcopy(SMALL)
    data["recipes"].append(recipe("no_grams", 15, 2, *items))
    return catalog_from_dict(data)


def test_optional_without_grams_loads_and_ignored():
    cat = _with_recipe(("egg", 100), ("herb", None, True))
    assert levels(reachable_dishes({"egg"}, cat))["no_grams"] == 0


def test_required_without_grams_missing_means_one_pack():
    cat = _with_recipe(("egg", 100), ("cheese", None))
    opt = dish_option(cat.recipe("no_grams"), {"egg"}, cat)
    assert opt.missing == {"cheese"}
    assert opt.to_dict(cat)["missing"][0]["packs"] == 1
    assert opt.metrics.buy_cost == 200  # одна упаковка сыра


def test_required_without_grams_present_is_enough():
    cat = _with_recipe(("egg", 100), ("cheese", None))
    assert dish_option(cat.recipe("no_grams"), {"egg": None, "cheese": 10}, cat).level == 0


def test_required_without_grams_marks_nutrition_incomplete():
    cat = _with_recipe(("egg", 100), ("cheese", None))
    m = dish_option(cat.recipe("no_grams"), {}, cat).metrics
    assert m.nutrition_complete is False
    assert m.kcal == 75  # только яйцо: 150 ккал / 2 порции
    assert "milk" in m.allergens  # аллерген сыра учтён, хоть граммы и не указаны
    assert dish_option(cat.recipe("omelette"), {}, cat).metrics.nutrition_complete is True


def test_zero_grams_still_rejected():
    import pytest as _pytest

    from dishgraph import CatalogError

    with _pytest.raises(CatalogError, match="qty_g"):
        _with_recipe(("egg", 0))
