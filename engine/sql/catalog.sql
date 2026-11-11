-- Каталог для движка одним JSON-документом (схема db/schema.sql).
-- Сервер выполняет запрос при старте и передаёт результат в dishgraph.catalog_from_dict(...).
-- Личные рецепты (author_id IS NOT NULL) сюда не попадают.
SELECT json_build_object(
    'ingredients', (
        SELECT COALESCE(json_agg(json_build_object(
            'code',            i.code,
            'name',            i.name,
            'is_staple',       i.is_staple,
            'package_g',       i.package_g,
            'package_price',   i.package_price,
            'kcal',            i.kcal,
            'protein',         i.protein,
            'fat',             i.fat,
            'carbs',           i.carbs,
            'display_unit',    i.display_unit,
            'grams_per_piece', i.grams_per_piece,
            'allergens', COALESCE((SELECT json_agg(a.code ORDER BY a.code)
                                   FROM ingredient_allergens ia
                                   JOIN allergens a ON a.id = ia.allergen_id
                                   WHERE ia.ingredient_id = i.id), '[]'::json),
            'aliases',   COALESCE((SELECT json_agg(al.alias ORDER BY al.alias)
                                   FROM ingredient_aliases al
                                   WHERE al.ingredient_id = i.id), '[]'::json)
        ) ORDER BY i.id), '[]'::json)
        FROM ingredients i
    ),
    'recipes', (
        SELECT COALESCE(json_agg(json_build_object(
            'id',              r.id::text,
            'title',           r.title,
            'description',     r.description,
            'servings',        r.servings,
            'cook_time_min',   r.cook_time_min,
            'needs_microwave', r.needs_microwave,
            'needs_stove',     r.needs_stove,
            'needs_oven',      r.needs_oven,
            'no_cook',         r.no_cook,
            'image_url',       r.image_url,
            'steps', COALESCE((SELECT json_agg(s.instruction ORDER BY s.step_no)
                               FROM recipe_steps s
                               WHERE s.recipe_id = r.id), '[]'::json),
            'items', COALESCE((SELECT json_agg(json_build_object(
                                   'code',        i.code,
                                   'qty_g',       ri.qty_g,
                                   'is_optional', ri.is_optional) ORDER BY i.code)
                               FROM recipe_ingredients ri
                               JOIN ingredients i ON i.id = ri.ingredient_id
                               WHERE ri.recipe_id = r.id), '[]'::json)
        ) ORDER BY r.id), '[]'::json)
        FROM recipes r
        WHERE r.author_id IS NULL
    )
) AS catalog;
