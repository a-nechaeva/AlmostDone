"""Каталог из дампа pg_dump (db/seed.sql) без PostgreSQL."""
from almostdone_server.repositories.catalog import SeedCatalogRepository
from ..support.paths import SERVER_ROOT

DUMP = """\
COPY public.allergens (id, code, name) FROM stdin;
1\tmilk\tМолоко
\\.

COPY public.ingredients (id, code, name, is_staple, display_unit, grams_per_piece, kcal, protein, fat, carbs, package_g, package_price) FROM stdin;
2\tmilk\tМолоко\tf\tml\t\\N\t60\t3\t3.2\t4.7\t1000\t110.50
1\tsalt\tСоль\tt\tg\t\\N\t0\t0\t0\t0\t1000\t60
\\.

COPY public.recipes (id, title, description, servings, cook_time_min, needs_microwave, needs_stove, needs_oven, image_url, author_id, no_cook) FROM stdin;
7\tКаша\tСтрока\\nвторая\t2\t10\tf\tt\tf\thttps://photos.example/7.jpg\t\\N\tf
8\tЛичный\t\\N\t1\t5\tf\tf\tf\t\\N\t42\tt
\\.

COPY public.ingredient_aliases (ingredient_id, alias) FROM stdin;
2\tмолочко
\\.

COPY public.ingredient_allergens (ingredient_id, allergen_id) FROM stdin;
2\t1
\\.

COPY public.recipe_ingredients (recipe_id, ingredient_id, qty_g, is_optional) FROM stdin;
7\t2\t200\tf
7\t1\t\\N\tt
\\.

COPY public.recipe_steps (recipe_id, step_no, instruction, duration_min) FROM stdin;
7\t2\tПодать\t\\N
7\t1\tСварить\t10
\\.
"""


def test_dump_gives_the_same_records_as_postgres_loader(tmp_path):
    path = tmp_path / "seed.sql"
    path.write_text(DUMP, encoding="utf-8")
    data = SeedCatalogRepository(path).load()
    ingredients = {i["code"]: i for i in data["ingredients"]}
    assert ingredients["milk"]["package_price"] == 110.5 and ingredients["milk"]["grams_per_piece"] is None
    assert ingredients["milk"]["allergens"] == ["milk"] and ingredients["milk"]["aliases"] == ["молочко"]
    assert ingredients["salt"]["is_staple"] is True
    [recipe] = data["recipes"]  # личные рецепты (author_id) не входят в каталог
    assert recipe["id"] == "7" and recipe["description"] == "Строка\nвторая" and recipe["needs_stove"] is True
    assert recipe["image_url"] == "https://photos.example/7.jpg"
    assert recipe["items"] == [{"code": "salt", "qty_g": None, "is_optional": True},
                               {"code": "milk", "qty_g": 200.0, "is_optional": False}]
    assert recipe["steps"] == ["Сварить", "Подать"]
    assert recipe["step_details"][0] == {"number": 1, "text": "Сварить", "minutes": 10}


def test_project_seed_loads():
    data = SeedCatalogRepository(SERVER_ROOT.parent / "db/seed.sql").load()
    assert len(data["recipes"]) > 100 and len(data["ingredients"]) > 100


DIET_DUMP = DUMP + """
COPY public.diets (id, kind, name, description) FROM stdin;
1\tpevzner\tСтол №1\t\\N
12\tdiet\tВегетарианство\t\\N
13\tdiet\tВеганство\t\\N
16\tdiet\tБезлактозная\t\\N
\\.

COPY public.ingredient_categories (ingredient_id, category_id) FROM stdin;
2\t5
\\.

COPY public.diet_excluded_categories (diet_id, category_id) FROM stdin;
1\t5
13\t5
\\.

COPY public.diet_excluded_allergens (diet_id, allergen_id) FROM stdin;
16\t1
\\.
"""


def test_dump_loads_ingredient_diet_exclusions(tmp_path):
    path = tmp_path / "seed.sql"
    path.write_text(DIET_DUMP, encoding="utf-8")
    data = SeedCatalogRepository(path).load()
    ingredients = {i["code"]: i for i in data["ingredients"]}
    # Категория «молочные» исключена веганством, аллерген «молоко» — безлактозной диетой;
    # правило певзнеровского стола (kind != 'diet') игнорируется.
    assert ingredients["milk"]["diet_exclusions"] == ["lactose_free", "vegan"]
    assert ingredients["salt"]["diet_exclusions"] == []


def test_project_seed_marks_animal_ingredients_for_vegan_diet():
    data = SeedCatalogRepository(SERVER_ROOT.parent / "db/seed.sql").load()
    ingredients = {i["name"]: i for i in data["ingredients"]}
    egg = ingredients["Яйцо куриное"]
    assert "vegan" in egg["diet_exclusions"] and "vegetarian" not in egg["diet_exclusions"]
    guanciale = ingredients["Гуанчале"]
    assert "vegetarian" in guanciale["diet_exclusions"] and "vegan" in guanciale["diet_exclusions"]


def test_export_from_seed_hides_carbonara_for_vegan():
    from almostdone_server.adapters.engine import DishgraphGateway
    from almostdone_server.services.catalog import Catalog

    catalog = Catalog(SeedCatalogRepository(SERVER_ROOT.parent / "db/seed.sql"), DishgraphGateway())
    exported = catalog.export()
    carbonara = next(r for r in exported["recipes"] if r["title"] == "Спагетти карбонара")
    assert carbonara["dietary_facts"]["vegan"] is False
    assert carbonara["dietary_facts"]["vegetarian"] is False
