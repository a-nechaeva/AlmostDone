-- Three bundled recipes had no cooking method. Diet rules that forbid a method
-- (user_recipe_visibility joins recipe_cooking_methods) could not see them, and
-- the equipment filter treated them as needing nothing.
--
-- "Шопский салат" was also marked no_cook, although its first step chars the
-- pepper over an open flame. A no_cook recipe may only carry the method
-- "Без термической обработки", so the flag is corrected before the method is added.
-- Recipes are matched by id and title; a recipe that already has a method is left alone.

UPDATE public.recipes r
SET no_cook = false, needs_stove = true
WHERE r.id = 128 AND r.title = 'Шопский салат' AND r.author_id IS NULL AND r.no_cook
  AND NOT EXISTS (SELECT 1 FROM public.recipe_cooking_methods x WHERE x.recipe_id = r.id);

INSERT INTO public.recipe_cooking_methods (recipe_id, method_id)
SELECT r.id, m.id
FROM (VALUES
    (128, 'Шопский салат', 'Жарка / Обжаривание'),  -- pepper charred over an open flame
    (412, 'Мухаммара',     'Жарка / Обжаривание'),  -- peppers charred, walnuts toasted in a dry pan
    (451, 'Кохуке',        'Варка / Тушение')       -- glaze melted over a water bath
) AS v(recipe_id, title, method)
JOIN public.recipes r ON r.id = v.recipe_id AND r.title = v.title AND r.author_id IS NULL AND NOT r.no_cook
JOIN public.cooking_methods m ON m.name = v.method
WHERE NOT EXISTS (SELECT 1 FROM public.recipe_cooking_methods x WHERE x.recipe_id = r.id);
