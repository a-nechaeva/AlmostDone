-- One product must be one catalogue row. A pantry product is matched to recipe
-- lines by ingredient id, so "Мука пшеничная" in a pantry did not cover the 112
-- recipes that ask for "Мука", and "always in stock" was set on "Масло
-- подсолнечное" (3 recipes) instead of "Масло растительное" (153 recipes).
--
-- Each pair is (duplicate, target), matched by ingredient code. Recipe lines,
-- aliases, allergens, categories, pantry rows and favourites of the duplicate move
-- to the target, then the duplicate is deleted; its name stays searchable as an
-- alias. A pair is skipped when either code is absent, so the file is safe for a
-- database whose catalogue differs from db/seed.sql.

CREATE TEMP TABLE ingredient_merge_codes (
    duplicate_code text PRIMARY KEY,
    target_code text NOT NULL
) ON COMMIT DROP;

INSERT INTO ingredient_merge_codes (duplicate_code, target_code) VALUES
    -- Same product under two names
    ('ing_14fd32dd74115fe5', 'ing_9f5aff656efd8171'),  -- Мука пшеничная -> Мука
    ('ing_db84ea5b310b4ac9', 'ing_94735c5d0f98f9bb'),  -- Масло подсолнечное -> Масло растительное
    ('ing_b1e510d5f2768b38', 'ing_54af9e8fba188b3a'),  -- Капуста белокочанная -> Капуста
    ('ing_3477b62e74f3e078', 'ing_e839f9e5f64c687e'),  -- Томатный кетчуп -> Кетчуп
    ('ing_c29673e024a28f25', 'ing_d13ec2bae7806ca5'),  -- Сушёный лайм лууми -> Сушёный лайм луми
    ('ing_91ab086130506d34', 'ing_1a27b5d34b3e25a7'),  -- Перец чёрный молотый -> Перец чёрный
    ('ing_c60f734ca6f6fe41', 'ing_a9e4be6b46a4fe44'),  -- Тёртый кокос -> Кокос тёртый
    ('ing_309fb3b47f1f290d', 'ing_eb79763086e38818'),  -- Колбаса копчёная -> Копчёная колбаса
    ('ing_353df0d35175ba4a', 'ing_e4e8ba6430e3f192'),  -- Лепёшка -> Лепёшки
    ('ing_1b504827ddbf9e81', 'ing_084371a10e55dcf5'),  -- Чёрные оливки -> Оливки чёрные
    ('ing_d69e7b7754c00946', 'ing_0d385b371e26a239'),  -- Копчёная колбаса рукворст -> Копчёная колбаса рокворст
    ('ing_12447adc3d359407', 'ing_edfa174d012dac1a'),  -- Паста ачиоте (рекадо рохо) -> Паста ачиоте
    ('ing_e6dce269f245accb', 'ing_ccbad22d9d717dab'),  -- Паста самбал -> Самбал
    ('ing_219206fce0fec761', 'ing_67150e22f888859a'),  -- Смесь бахарат -> Бахарат
    ('ing_386c3d9f6fbee18a', 'ing_9eda68989522c839'),  -- Листья салата -> Салат листовой
    ('ing_baa12ddf52abb45b', 'ing_67599c5024edd328'),  -- Яблоки кислых сортов -> Кислые яблоки
    ('ing_40b3982e4d3a7c58', 'ing_a8fa07fe9d97603c'),  -- Перец тимур -> Сычуаньский перец тимур
    ('ing_cd466d1fd564b097', 'ing_f8f3d2c774368db3'),  -- Половинки орехов -> Грецкий орех
    ('ing_01b7bb9911de349e', 'ing_50ea3a471feaff34'),  -- Вырезка -> Говяжья вырезка
    ('ing_955bf5851e1731fc', 'ing_6030f78f00f6b884'),  -- Грудинка -> Говяжья грудинка
    -- Same product named after its role in one dish
    ('ing_ad9c92e577a7b395', 'ing_9f5aff656efd8171'),  -- Мука для блинов -> Мука
    ('ing_d3e697b3e8befee9', 'ing_9f5aff656efd8171'),  -- Мука для начинки -> Мука
    ('ing_25a9ee6f16f660fd', 'ing_9f5aff656efd8171'),  -- Мука для основы -> Мука
    ('ing_3a450de455f5a954', 'ing_9f5aff656efd8171'),  -- Мука для роши -> Мука
    ('ing_8ded051cba77f898', 'ing_9f5aff656efd8171'),  -- Мука для теста -> Мука
    ('ing_7db959e12f7cd3a7', 'ing_a64931804dc4ddba'),  -- Сахар в начинку -> Сахар
    ('ing_9889f67d451ec4f5', 'ing_a64931804dc4ddba'),  -- Сахар для глазури -> Сахар
    ('ing_43ad36bec83c6b71', 'ing_a64931804dc4ddba'),  -- Сахар для корочки -> Сахар
    ('ing_5479a097ded99471', 'ing_a64931804dc4ddba'),  -- Сахар для обваливания -> Сахар
    ('ing_677a24ed684bb7f5', 'ing_a64931804dc4ddba'),  -- Сахар для соуса -> Сахар
    ('ing_8cbbb55b5c7ee73c', 'ing_5b67906812f9ce35'),  -- Соль в тесто -> Соль
    ('ing_b3538df2d557c8a3', 'ing_69f91741a4c2027f'),  -- Молоко в бешамель -> Молоко
    ('ing_1541e605a59936f9', 'ing_69f91741a4c2027f'),  -- Молоко для крема -> Молоко
    ('ing_fb73721c2185836c', 'ing_f9488f0bc6429a47'),  -- Масло в тесто -> Масло сливочное
    ('ing_a14b22f41a66f6d9', 'ing_f9488f0bc6429a47'),  -- Масло для слоения -> Масло сливочное
    ('ing_be3bc147ac275713', 'ing_f9488f0bc6429a47'),  -- Сливочное масло для теста -> Масло сливочное
    ('ing_387ea3f3f83b8fdf', 'ing_94735c5d0f98f9bb'),  -- Растительное масло для соуса -> Масло растительное
    ('ing_935c05715fbe80a3', 'ing_5e3d8980c5685bfd'),  -- Горчица для соуса -> Горчица
    ('ing_0806c1978bbf37ea', 'ing_d5080a8150c44fc0'),  -- Уксус для соуса -> Уксус
    ('ing_835a14b17015bc8b', 'ing_a8cc57929454281a'),  -- Чёрный уксус для соуса -> Чёрный уксус чжэньцзян
    ('ing_668d670e80f7a441', 'ing_0a7d9d11e8664161'),  -- Шоколад для глазури -> Тёмный шоколад
    ('ing_f2605f24a452bb03', 'ing_9d437ad02b674581'),  -- Какао для глазури -> Какао-порошок
    ('ing_2c6ca5dee3ed115d', 'ing_8214cfa2ad659987'),  -- Лук для подачи -> Лук репчатый
    ('ing_4e0942121b5f7bce', 'ing_67150e22f888859a'),  -- Бахарат для кабсы -> Бахарат
    -- Same product named after its state
    ('ing_6bfe32a37639492c', 'ing_0611a1b7ac680b4a'),  -- Горячая вода -> Вода
    ('ing_ede79425d0d6c10e', 'ing_69f91741a4c2027f'),  -- Горячее молоко -> Молоко
    ('ing_774b010a43c80ff1', 'ing_b7d7a56889d14551'),  -- Холодный бульон -> Бульон
    ('ing_983d5363213a3626', 'ing_6362b9a2160b3580'),  -- Картофель сырой -> Картофель
    ('ing_a0bce04fce034162', 'ing_2503548b0a13a2b9'),  -- Свежий тунец -> Тунец
    ('ing_5ddccf0ba57f2385', 'ing_3feced8147f8df46'),  -- Нут сухой -> Нут
    ('ing_fef1502b60834d77', 'ing_1c4ab4239538af48')   -- Чеснок головками -> Чеснок
;

CREATE TEMP TABLE ingredient_merge ON COMMIT DROP AS
SELECT d.id AS duplicate_id, t.id AS target_id, d.name AS duplicate_name, t.name AS target_name
FROM ingredient_merge_codes c
JOIN public.ingredients d ON d.code = c.duplicate_code
JOIN public.ingredients t ON t.code = c.target_code;

-- Recipe lines (bundled and personal recipes). A recipe that listed the product
-- twice gets one line: quantities add up, and the line stays optional only if
-- every part was optional.
CREATE TEMP TABLE merged_recipe_lines ON COMMIT DROP AS
SELECT ri.recipe_id, m.target_id AS ingredient_id,
       bool_and(ri.is_optional) AS is_optional,
       CASE WHEN bool_and(ri.is_optional) THEN sum(ri.qty_g)
            ELSE sum(ri.qty_g) FILTER (WHERE NOT ri.is_optional) END AS qty_g
FROM public.recipe_ingredients ri
JOIN (SELECT duplicate_id AS ingredient_id, target_id FROM ingredient_merge
      UNION ALL
      SELECT DISTINCT target_id, target_id FROM ingredient_merge) m ON m.ingredient_id = ri.ingredient_id
GROUP BY ri.recipe_id, m.target_id
HAVING bool_or(ri.ingredient_id <> m.target_id);

DELETE FROM public.recipe_ingredients ri
USING ingredient_merge m
WHERE ri.ingredient_id = m.duplicate_id;

INSERT INTO public.recipe_ingredients (recipe_id, ingredient_id, qty_g, is_optional)
SELECT recipe_id, ingredient_id, qty_g, is_optional FROM merged_recipe_lines
ON CONFLICT (recipe_id, ingredient_id) DO UPDATE
SET qty_g = EXCLUDED.qty_g, is_optional = EXCLUDED.is_optional;

-- Search and receipt recognition keep finding the product by its old names.
INSERT INTO public.ingredient_aliases (ingredient_id, alias)
SELECT m.target_id, a.alias
FROM ingredient_merge m
JOIN public.ingredient_aliases a ON a.ingredient_id = m.duplicate_id
UNION
SELECT target_id, duplicate_name FROM ingredient_merge
ON CONFLICT DO NOTHING;

INSERT INTO public.ingredient_allergens (ingredient_id, allergen_id)
SELECT DISTINCT m.target_id, x.allergen_id
FROM ingredient_merge m
JOIN public.ingredient_allergens x ON x.ingredient_id = m.duplicate_id
ON CONFLICT DO NOTHING;

INSERT INTO public.ingredient_categories (ingredient_id, category_id)
SELECT DISTINCT m.target_id, x.category_id
FROM ingredient_merge m
JOIN public.ingredient_categories x ON x.ingredient_id = m.duplicate_id
ON CONFLICT DO NOTHING;

-- User data follows the product. Pantry quantities add up; NULL means "in stock,
-- amount unknown" and wins. The API notices the change through state_hash and
-- raises state_version on the next request.
INSERT INTO public.user_pantry AS p (user_id, ingredient_id, qty_g)
SELECT d.user_id, m.target_id,
       CASE WHEN bool_or(d.qty_g IS NULL) THEN NULL ELSE LEAST(sum(d.qty_g), 999999.99) END
FROM public.user_pantry d
JOIN ingredient_merge m ON m.duplicate_id = d.ingredient_id
GROUP BY d.user_id, m.target_id
ON CONFLICT (user_id, ingredient_id) DO UPDATE
SET qty_g = CASE WHEN p.qty_g IS NULL OR EXCLUDED.qty_g IS NULL THEN NULL
                 ELSE LEAST(p.qty_g + EXCLUDED.qty_g, 999999.99) END;

INSERT INTO public.favorite_ingredients (user_id, ingredient_id, added_at)
SELECT f.user_id, m.target_id, min(f.added_at)
FROM public.favorite_ingredients f
JOIN ingredient_merge m ON m.duplicate_id = f.ingredient_id
GROUP BY f.user_id, m.target_id
ON CONFLICT (user_id, ingredient_id) DO NOTHING;

-- The target keeps its own values. It only inherits "always in stock" and the unit
-- coefficients it lacks.
UPDATE public.ingredients t
SET is_staple = t.is_staple OR d.is_staple,
    grams_per_piece = COALESCE(t.grams_per_piece, d.grams_per_piece),
    grams_per_ml = COALESCE(t.grams_per_ml, d.grams_per_ml)
FROM (SELECT m.target_id,
             bool_or(i.is_staple) AS is_staple,
             max(i.grams_per_piece) AS grams_per_piece,
             max(i.grams_per_ml) AS grams_per_ml
      FROM ingredient_merge m
      JOIN public.ingredients i ON i.id = m.duplicate_id
      GROUP BY m.target_id) d
WHERE t.id = d.target_id
  AND ((d.is_staple AND NOT t.is_staple)
       OR (t.grams_per_piece IS NULL AND d.grams_per_piece IS NOT NULL)
       OR (t.grams_per_ml IS NULL AND d.grams_per_ml IS NOT NULL));

-- Remaining rows of the duplicate (aliases, allergens, categories, pantry,
-- favourites) go with it: those foreign keys are ON DELETE CASCADE.
DELETE FROM public.ingredients i
USING ingredient_merge m
WHERE i.id = m.duplicate_id;
