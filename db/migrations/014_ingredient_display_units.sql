-- Liquids are shown in millilitres and countable products in pieces. Until now
-- display_unit was 'g' for every ingredient: "Яйцо куриное 300 г", "Молоко 206 г".
--
-- The API shows a quantity as grams divided by the coefficient, so a switch alone
-- would turn 200 g of cream into 198.019802 ml. Three things therefore change together:
--   1. display_unit of the listed ingredients, when the coefficient exists;
--   2. recipe quantities of every ingredient shown in ml or pieces are rounded to a
--      number a cook would write (100 ml, 0.5 or 2 pieces) and stored back in grams;
--   3. pantry amounts of those ingredients, entered in grams so far, are converted
--      to the new unit; clients compare units and would otherwise ask to re-enter them.
-- The unit belongs to the ingredient, so personal recipes are rounded by the same rule.
-- Run after 009 (coefficients) and after 013 (merged quantities are rounded once).

CREATE TEMP TABLE new_units (
    code text PRIMARY KEY,
    unit text NOT NULL CHECK (unit IN ('ml', 'pcs'))
) ON COMMIT DROP;

INSERT INTO new_units (code, unit) VALUES
    ('ing_8214cfa2ad659987', 'pcs'),  -- Лук репчатый
    ('ing_94735c5d0f98f9bb', 'ml'),  -- Масло растительное
    ('ing_5080f64e5d37ea5c', 'pcs'),  -- Яйцо куриное
    ('ing_0611a1b7ac680b4a', 'ml'),  -- Вода
    ('ing_69f91741a4c2027f', 'ml'),  -- Молоко
    ('ing_14a4780585e50d6a', 'ml'),  -- Масло оливковое
    ('ing_e2162431045c69e8', 'pcs'),  -- Лимон
    ('ing_7bb9e91a144d2836', 'pcs'),  -- Лайм
    ('ing_3caca706865b1943', 'ml'),  -- Кокосовое молоко
    ('ing_44731879aed2c37b', 'pcs'),  -- Лук красный
    ('ing_3114ece82c6e01a9', 'ml'),  -- Сливки
    ('ing_806d0f13effa3beb', 'ml'),  -- Соус соевый
    ('ing_b7f4693039de2bba', 'pcs'),  -- Шалот
    ('ing_c3d66be69bae22f7', 'ml'),  -- Вино белое сухое
    ('ing_234a7b19ef28f34c', 'ml'),  -- Рыбный соус
    ('ing_d5080a8150c44fc0', 'ml'),  -- Уксус
    ('ing_02a6366a177076ad', 'ml'),  -- Бульон говяжий
    ('ing_fbfbeef2dd1eef71', 'ml'),  -- Сливки 33%
    ('ing_10164541aec1f5f4', 'ml'),  -- Бульон куриный
    ('ing_6ca73d503ca3dcca', 'pcs'),  -- Подорожник
    ('ing_a04c4b9b4e595433', 'pcs'),  -- Авокадо
    ('ing_384d9b040efc72c4', 'ml'),  -- Винный уксус
    ('ing_58a686c981ca848e', 'ml'),  -- Кефир
    ('ing_dd786d8ed9d32aff', 'ml'),  -- Кунжутное масло
    ('ing_650b663caaf9bccc', 'ml'),  -- Мирин
    ('ing_14e2f4a3b901e6c8', 'ml'),  -- Вино красное сухое
    ('ing_1ca7630ef99fedc1', 'ml'),  -- Вино шаосинское
    ('ing_51ed7c37c730a2b3', 'ml'),  -- Даси
    ('ing_d08e59585dfc92e1', 'pcs'),  -- Плантайн зелёный
    ('ing_230dd02fa49a5a03', 'ml'),  -- Белый уксус
    ('ing_4c851ed4c2ae3163', 'pcs'),  -- Пита
    ('ing_e856c55070fd163b', 'ml'),  -- Соус соевый тёмный
    ('ing_ff76bee750f4e0f9', 'ml'),  -- Уксус винный красный
    ('ing_90f660487ae6557b', 'pcs'),  -- Багет
    ('ing_45f61f3ca34cb2bf', 'ml'),  -- Бульон мясной
    ('ing_a6fd0e5fe13f0371', 'ml'),  -- Вода флёрдоранж
    ('ing_4ae837dc2ffb11ad', 'ml'),  -- Вустерский соус
    ('ing_ca21b9d84c6c8d21', 'ml'),  -- Гранатовый соус
    ('ing_e4e8ba6430e3f192', 'pcs'),  -- Лепёшки
    ('ing_5b8f0dec3d533054', 'ml'),  -- Соус соевый светлый
    ('ing_4851b1ee2cb0d571', 'ml'),  -- Томатный соус
    ('ing_b8b8474cb00f6e86', 'pcs'),  -- Апельсин
    ('ing_e839f9e5f64c687e', 'ml'),  -- Кетчуп
    ('ing_4991a645bdf495dd', 'ml'),  -- Розовая вода
    ('ing_f14adf22ad3a114f', 'ml'),  -- Саке
    ('ing_b4f49c2f3aa354c0', 'ml'),  -- Сливки 20%
    ('ing_47b0070b88dec8b0', 'pcs'),  -- Ананас
    ('ing_0c76090704763acb', 'pcs'),  -- Булочки
    ('ing_b7d7a56889d14551', 'ml'),  -- Бульон
    ('ing_5585374d6652e15c', 'ml'),  -- Вино красное
    ('ing_88bba507f5bc6a24', 'ml'),  -- Кечап манис
    ('ing_a4998d03c69153fc', 'ml'),  -- Кирш
    ('ing_6e329e080950f78a', 'ml'),  -- Концентрированное молоко
    ('ing_4369ae1f923bbbe8', 'ml'),  -- Коньяк
    ('ing_a070cf5c1b956cc7', 'ml'),  -- Лимонный сок
    ('ing_172608c215076180', 'ml'),  -- Масло горчичное
    ('ing_816ad581c21510bf', 'ml'),  -- Масло оливковое extra virgin
    ('ing_dbaf2b9f0eb63f8a', 'ml'),  -- Масло пальмовое красное
    ('ing_a50951dec7f5c51a', 'ml'),  -- Светлое пиво
    ('ing_a0d06fd1f1d8ea6c', 'ml'),  -- Соус Лисано
    ('ing_856e5cf2184a8b7b', 'ml'),  -- Соус жуг
    ('ing_de71cdc48a8c6825', 'ml'),  -- Тёмное пиво
    ('ing_5966a27180b890ef', 'ml'),  -- Уксус рисовый
    ('ing_636aceda5c60993f', 'ml'),  -- Уксус хересный
    ('ing_658f381214e73c12', 'ml'),  -- Уксус яблочный
    ('ing_b0ffc9ef7e7a3cf0', 'ml'),  -- Устричный соус
    ('ing_3e144f074bd33a1c', 'ml'),  -- Анисовый ликёр
    ('ing_e462818568898d13', 'ml'),  -- Апельсиновый сок
    ('ing_6182fbc92d4f5cb7', 'pcs'),  -- Банан
    ('ing_7563895ec9dff0ac', 'ml'),  -- Борщ из отрубей
    ('ing_26c36888d4bd7f28', 'ml'),  -- Брусничный соус
    ('ing_18ced12062b87f0b', 'pcs'),  -- Булочки для хот-дога
    ('ing_a4466bc12d1f28b0', 'pcs'),  -- Булочки мантоу
    ('ing_1f416e6e624bfa5c', 'ml'),  -- Бульон бараний
    ('ing_731e56014e0135dc', 'ml'),  -- Бульон овощной
    ('ing_f38c5d1ba59fc1f7', 'ml'),  -- Бульон рыбный
    ('ing_a60459b0b9e32d05', 'ml'),  -- Бульон телячий
    ('ing_fb75c8834dd7cc82', 'ml'),  -- Газированная вода
    ('ing_7bbe0e1ba4b69382', 'ml'),  -- Гранатовая патока
    ('ing_b42a0b9fd6a00c0c', 'pcs'),  -- Грейпфрут
    ('ing_adcc30a4d0380876', 'pcs'),  -- Зелёные бананы
    ('ing_11649ed3f1303cff', 'pcs'),  -- Зелёные бананы матоке
    ('ing_502c3029ecb1aca3', 'ml'),  -- Золотой сироп
    ('ing_09099282aac695d5', 'pcs'),  -- Киви
    ('ing_342b2cadd629badc', 'pcs'),  -- Кипрская пита
    ('ing_f2613212dd2f039c', 'ml'),  -- Кленовый сироп
    ('ing_029f06b7b686cdea', 'ml'),  -- Кокосовое масло
    ('ing_6ae716709b482fe2', 'ml'),  -- Кокосовые сливки
    ('ing_7dd3b84d2af5c0c0', 'pcs'),  -- Корейская груша
    ('ing_ada64fb2f341285f', 'ml'),  -- Крепкий эспрессо
    ('ing_a0625968e29c22bb', 'pcs'),  -- Кукуруза початками
    ('ing_e8716ac094412cec', 'pcs'),  -- Лепёшка наан
    ('ing_71688ec87941115b', 'pcs'),  -- Лепёшка пиде
    ('ing_ff66960938de8f6d', 'pcs'),  -- Лепёшки сомун
    ('ing_6f95d6b852db3bb6', 'pcs'),  -- Лепёшки таббун
    ('ing_d90404d65b3ed726', 'ml'),  -- Мальтозный сироп
    ('ing_73a59921fa062ecb', 'pcs'),  -- Маракуйя
    ('ing_79844ac37df050fc', 'ml'),  -- Марсала
    ('ing_4019b2a8e96bed36', 'ml'),  -- Масло пальмовое
    ('ing_565de69a603ebf4d', 'ml'),  -- Молоко обезжиренное
    ('ing_9c2573823bc2e14a', 'ml'),  -- Мясная подлива
    ('ing_ea91be119f1dd871', 'ml'),  -- Огуречный рассол
    ('ing_7449dd8424ca7625', 'ml'),  -- Острый перечный соус
    ('ing_7bdaf26c45d9e31e', 'ml'),  -- Пальмовое масло денде
    ('ing_9453127deb29344b', 'ml'),  -- Пахта
    ('ing_b1cb056f933d534f', 'pcs'),  -- Плантайн
    ('ing_99282d294b4989b1', 'pcs'),  -- Пресная лепёшка чурек
    ('ing_8810d29635f5d12e', 'ml'),  -- Ром
    ('ing_6167d0df49e65060', 'ml'),  -- Свиная кровь
    ('ing_831a4225e03807d8', 'ml'),  -- Сладкое вино
    ('ing_557dc700883ef5f1', 'ml'),  -- Сливки 30%
    ('ing_f22fceb6dd681abb', 'pcs'),  -- Слоёная лепёшка фатир
    ('ing_ba62be6b38b69039', 'ml'),  -- Сок лайма
    ('ing_22750c03cd1e32f1', 'ml'),  -- Соус из голубого сыра
    ('ing_ea170c0e9dab86ef', 'ml'),  -- Соус окономи
    ('ing_69dc1800ade951af', 'ml'),  -- Соус хойсин
    ('ing_73fabe44ad08c4f9', 'ml'),  -- Соус шито
    ('ing_4322822bc92815df', 'ml'),  -- Тамариндовый соус
    ('ing_6a2ff88bba6be77b', 'ml'),  -- Томатное пюре
    ('ing_3068c3c1b89942f9', 'ml'),  -- Томатный сок
    ('ing_7cf9f87a547fa4ba', 'pcs'),  -- Тонкая лепёшка
    ('ing_0090b21710c0eba0', 'pcs'),  -- Тонкий лаваш
    ('ing_801caaaf7bf2ee30', 'ml'),  -- Тёмное бельгийское пиво
    ('ing_6e76ad51d3e2a244', 'ml'),  -- Тёмное пиво стаут
    ('ing_c01137e05284d07e', 'ml'),  -- Уксус 9%
    ('ing_89aed53d19cc1102', 'ml'),  -- Уксус солодовый
    ('ing_c67bc041961fa6f7', 'ml'),  -- Финиковый сироп дибс
    ('ing_30a11c0b7b37f5eb', 'ml'),  -- Херес
    ('ing_a8cc57929454281a', 'ml'),  -- Чёрный уксус чжэньцзян
    ('ing_0d5cf395040623a7', 'ml')  -- Яблочный сок
;

UPDATE public.ingredients AS i
SET display_unit = n.unit
FROM new_units n
WHERE i.code = n.code
  AND i.display_unit <> n.unit
  AND CASE n.unit WHEN 'ml' THEN i.grams_per_ml ELSE i.grams_per_piece END IS NOT NULL;

-- Millilitres. A multiple of 5 ml stays. Otherwise the roundest of 1000, 500, 100,
-- 50, 10 and 5 ml that is within 4 % wins, then the nearest multiple of 5 or 10 ml,
-- then the nearest whole millilitre. A candidate must convert back to
-- grams without a remainder (qty_g keeps two decimals) and may not move the amount
-- by more than 15 %; a line with no such candidate is left alone.
CREATE TEMP TABLE rounded_lines ON COMMIT DROP AS
SELECT DISTINCT ON (l.recipe_id, l.ingredient_id)
       l.recipe_id, l.ingredient_id, round(c.value * l.factor, 2) AS qty_g
FROM (SELECT ri.recipe_id, ri.ingredient_id, i.grams_per_ml AS factor, ri.qty_g / i.grams_per_ml AS shown
      FROM public.recipe_ingredients ri
      JOIN public.ingredients i ON i.id = ri.ingredient_id
      WHERE i.display_unit = 'ml' AND i.grams_per_ml IS NOT NULL AND ri.qty_g > 0) l
CROSS JOIN (VALUES (1, 1000), (2, 500), (3, 100), (4, 50), (5, 10), (6, 5), (7, 1)) AS g(rank, step)
CROSS JOIN LATERAL (SELECT round(l.shown / g.step) * g.step AS value) c
WHERE c.value > 0
  AND round(c.value * l.factor, 2) = c.value * l.factor
  AND abs(c.value - l.shown) / l.shown <= 0.15
ORDER BY l.recipe_id, l.ingredient_id,
         (g.rank <= 6 AND c.value = l.shown) DESC,
         (g.rank <= 6 AND abs(c.value - l.shown) / l.shown <= 0.04) DESC,
         CASE WHEN g.rank <= 6 AND abs(c.value - l.shown) / l.shown <= 0.04 THEN g.rank END,
         (g.rank <= 6) DESC,
         abs(c.value - l.shown),
         g.rank;

-- Pieces. Halves stay. Below three quarters of a piece the amount becomes a quarter
-- or a half, up to five pieces it is rounded to halves, above that to whole pieces.
-- A change of more than 35 % is not made.
INSERT INTO rounded_lines (recipe_id, ingredient_id, qty_g)
SELECT l.recipe_id, l.ingredient_id, round(c.value * l.factor, 2)
FROM (SELECT ri.recipe_id, ri.ingredient_id, i.grams_per_piece AS factor, ri.qty_g / i.grams_per_piece AS shown
      FROM public.recipe_ingredients ri
      JOIN public.ingredients i ON i.id = ri.ingredient_id
      WHERE i.display_unit = 'pcs' AND i.grams_per_piece IS NOT NULL AND ri.qty_g > 0) l
CROSS JOIN LATERAL (
    SELECT CASE WHEN l.shown * 2 = round(l.shown * 2) THEN l.shown
                WHEN l.shown < 0.375 THEN 0.25
                WHEN l.shown < 0.75 THEN 0.5
                WHEN l.shown < 5 THEN round(l.shown * 2) / 2
                ELSE round(l.shown)
           END AS value
) c
WHERE c.value <> l.shown
  AND abs(c.value - l.shown) / l.shown <= 0.35
  AND round(c.value * l.factor, 2) = c.value * l.factor;

UPDATE public.recipe_ingredients AS ri
SET qty_g = r.qty_g
FROM rounded_lines r
WHERE ri.recipe_id = r.recipe_id
  AND ri.ingredient_id = r.ingredient_id
  AND ri.qty_g <> r.qty_g;

-- Pantry. The amount moves to the nearest whole millilitre or to the nearest quarter
-- of a piece. The API keeps the unit of a pantry amount in user_api_state and falls
-- back to grams when the two disagree, so both are written: millilitres as the API
-- itself stores them (grams rounded to 0.01), pieces only when they convert back to
-- grams without a remainder. It notices the change through state_hash and raises
-- state_version on the next request.
CREATE TEMP TABLE converted_pantry ON COMMIT DROP AS
SELECT p.user_id, p.ingredient_id, p.code, p.unit, c.value, round(c.value * p.factor, 2) AS qty_g
FROM (SELECT up.user_id, up.ingredient_id, i.code, i.display_unit AS unit,
             CASE i.display_unit WHEN 'ml' THEN i.grams_per_ml ELSE i.grams_per_piece END AS factor,
             up.qty_g / CASE i.display_unit WHEN 'ml' THEN i.grams_per_ml ELSE i.grams_per_piece END AS shown
      FROM public.user_pantry up
      JOIN public.ingredients i ON i.id = up.ingredient_id
      WHERE i.display_unit IN ('ml', 'pcs') AND up.qty_g > 0
        AND CASE i.display_unit WHEN 'ml' THEN i.grams_per_ml ELSE i.grams_per_piece END IS NOT NULL) p
CROSS JOIN LATERAL (
    SELECT CASE p.unit WHEN 'ml' THEN greatest(round(p.shown), 1)
                       ELSE greatest(round(p.shown * 4) / 4, 0.25) END AS value
) c
WHERE (p.unit = 'ml' OR round(c.value * p.factor, 2) = c.value * p.factor)
  AND round(c.value * p.factor, 2) BETWEEN 0.01 AND 999999.99;

UPDATE public.user_pantry AS up
SET qty_g = c.qty_g
FROM converted_pantry c
WHERE up.user_id = c.user_id
  AND up.ingredient_id = c.ingredient_id
  AND up.qty_g <> c.qty_g;

INSERT INTO public.user_api_state AS s (user_id, pantry_display)
SELECT c.user_id,
       jsonb_object_agg(c.code, jsonb_build_object('value', trim_scale(c.value), 'unit', c.unit))
FROM converted_pantry c
GROUP BY c.user_id
ON CONFLICT (user_id) DO UPDATE
SET pantry_display = s.pantry_display || EXCLUDED.pantry_display;
