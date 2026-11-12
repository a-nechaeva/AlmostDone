-- Rules for the Pevzner tables 1-7, 9 and 10. Nine of the eighteen diets had no
-- rules at all, so a person who chose such a table saw every recipe.
--
-- The existing 13 categories cannot express the tables: there was nothing for
-- legumes, mushrooms, spicy, smoked or pickled food, alcohol. Ten narrow categories
-- are added; ingredients receive them in 011. A rule forbids a category, an
-- allergen or a cooking method. A category that already exists keeps its name and
-- is matched without regard to letter case, as its unique index does.

CREATE TEMP TABLE new_categories (name text PRIMARY KEY) ON COMMIT DROP;

INSERT INTO new_categories (name) VALUES
    ('Бобовые'),
    ('Грибы'),
    ('Острое'),
    ('Копчёности и колбасы'),
    ('Алкоголь'),
    ('Соленья и маринады'),
    ('Субпродукты'),
    ('Крепкие бульоны'),
    ('Крепкий чай и кофе'),
    ('Цельное молоко')
;

INSERT INTO public.categories (name)
SELECT n.name
FROM new_categories n
WHERE NOT EXISTS (SELECT 1 FROM public.categories c WHERE lower(c.name) = lower(n.name))
ORDER BY n.name;

CREATE TEMP TABLE new_rules (
    diet text NOT NULL,
    kind text NOT NULL CHECK (kind IN ('category', 'allergen', 'method')),
    value text NOT NULL,
    PRIMARY KEY (diet, kind, value)
) ON COMMIT DROP;

INSERT INTO new_rules (diet, kind, value) VALUES
    ('Стол №1', 'category', 'Бобовые'),
    ('Стол №1', 'category', 'Грибы'),
    ('Стол №1', 'category', 'Острое'),
    ('Стол №1', 'category', 'Копчёности и колбасы'),
    ('Стол №1', 'category', 'Соленья и маринады'),
    ('Стол №1', 'category', 'Алкоголь'),
    ('Стол №1', 'category', 'Крепкие бульоны'),
    ('Стол №1', 'category', 'Крепкий чай и кофе'),
    ('Стол №2', 'category', 'Острое'),
    ('Стол №2', 'category', 'Копчёности и колбасы'),
    ('Стол №2', 'category', 'Соленья и маринады'),
    ('Стол №2', 'category', 'Алкоголь'),
    ('Стол №2', 'category', 'Крепкие бульоны'),
    ('Стол №3', 'category', 'Острое'),
    ('Стол №3', 'category', 'Копчёности и колбасы'),
    ('Стол №3', 'category', 'Соленья и маринады'),
    ('Стол №3', 'category', 'Алкоголь'),
    ('Стол №3', 'category', 'Крепкий чай и кофе'),
    ('Стол №4', 'method', 'Жарка / Обжаривание'),
    ('Стол №4', 'category', 'Бобовые'),
    ('Стол №4', 'category', 'Грибы'),
    ('Стол №4', 'category', 'Острое'),
    ('Стол №4', 'category', 'Копчёности и колбасы'),
    ('Стол №4', 'category', 'Соленья и маринады'),
    ('Стол №4', 'category', 'Алкоголь'),
    ('Стол №4', 'category', 'Крепкие бульоны'),
    ('Стол №4', 'category', 'Крепкий чай и кофе'),
    ('Стол №4', 'category', 'Цельное молоко'),
    ('Стол №5', 'category', 'Бобовые'),
    ('Стол №5', 'category', 'Грибы'),
    ('Стол №5', 'category', 'Острое'),
    ('Стол №5', 'category', 'Копчёности и колбасы'),
    ('Стол №5', 'category', 'Соленья и маринады'),
    ('Стол №5', 'category', 'Алкоголь'),
    ('Стол №5', 'category', 'Крепкие бульоны'),
    ('Стол №6', 'category', 'Субпродукты'),
    ('Стол №6', 'category', 'Крепкие бульоны'),
    ('Стол №6', 'category', 'Бобовые'),
    ('Стол №6', 'category', 'Грибы'),
    ('Стол №6', 'category', 'Копчёности и колбасы'),
    ('Стол №6', 'category', 'Соленья и маринады'),
    ('Стол №6', 'category', 'Алкоголь'),
    ('Стол №6', 'category', 'Крепкий чай и кофе'),
    ('Стол №7', 'category', 'Крепкие бульоны'),
    ('Стол №7', 'category', 'Копчёности и колбасы'),
    ('Стол №7', 'category', 'Соленья и маринады'),
    ('Стол №7', 'category', 'Алкоголь'),
    ('Стол №7', 'category', 'Бобовые'),
    ('Стол №7', 'category', 'Грибы'),
    ('Стол №7', 'category', 'Крепкий чай и кофе'),
    ('Стол №7', 'category', 'Острое'),
    ('Стол №9', 'category', 'Алкоголь'),
    ('Стол №10', 'category', 'Алкоголь'),
    ('Стол №10', 'category', 'Копчёности и колбасы'),
    ('Стол №10', 'category', 'Соленья и маринады'),
    ('Стол №10', 'category', 'Крепкие бульоны'),
    ('Стол №10', 'category', 'Крепкий чай и кофе'),
    ('Стол №10', 'category', 'Острое')
;

-- A rule whose diet, category, allergen or method is absent from this database is
-- skipped: the catalogue may differ from db/seed.sql.
INSERT INTO public.diet_excluded_categories (diet_id, category_id)
SELECT d.id, c.id
FROM new_rules n
JOIN public.diets d ON d.name = n.diet
JOIN public.categories c ON lower(c.name) = lower(n.value)
WHERE n.kind = 'category'
ON CONFLICT DO NOTHING;

INSERT INTO public.diet_excluded_allergens (diet_id, allergen_id)
SELECT d.id, a.id
FROM new_rules n
JOIN public.diets d ON d.name = n.diet
JOIN public.allergens a ON a.code = n.value
WHERE n.kind = 'allergen'
ON CONFLICT DO NOTHING;

INSERT INTO public.diet_excluded_methods (diet_id, method_id)
SELECT d.id, m.id
FROM new_rules n
JOIN public.diets d ON d.name = n.diet
JOIN public.cooking_methods m ON m.name = n.value
WHERE n.kind = 'method'
ON CONFLICT DO NOTHING;

-- The diet tables have no trigger that invalidates the server's catalogue cache.
UPDATE public.catalog_revision SET revision = revision + 1 WHERE singleton;
