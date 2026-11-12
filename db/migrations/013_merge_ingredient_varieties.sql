-- Second pass over products that are one thing in a pantry but several rows in the
-- catalogue (the first pass was 005). A pantry product is matched to recipe lines by
-- ingredient id, so "Творог" at home did not cover a recipe that asks for "Творог 5–9 %",
-- and an orange at home did not cover "Цедра апельсина".
--
-- Three kinds of pairs (duplicate, target), matched by ingredient code:
--   * a part of a product (zest, juice) -> the product that is bought. The recipe
--     quantity becomes the number of whole pieces that give this much of the part;
--   * one product under two names;
--   * a variety or form the dish does not depend on -> the base product.
-- Products that differ in the kitchen stay separate: cooked rice and dry rice (the
-- weight differs three times), whipping cream and plain cream, dried mint and fresh
-- mint, dried thyme and fresh thyme, beef and lamb on the bone.
-- Merged on purpose: "Орегано сушёный" and "Майоран сушёный" (the plain rows are the
-- same dried herb, 1-5 g a dish), "Картофель варёный" (boiling hardly changes the
-- weight), "Курица на кости" (a chicken is bought on the bone anyway).
--
-- As in 005, recipe lines, aliases, allergens, categories, pantry rows and favourites
-- of the duplicate move to the target, then the duplicate is deleted; its name stays
-- searchable as an alias. A pair is skipped when either code is absent.
-- Run before 014: moved quantities are rounded there in the unit of the target.

CREATE TEMP TABLE ingredient_merge_codes (
    duplicate_code text PRIMARY KEY,
    target_code text NOT NULL,
    part_g_per_piece numeric CHECK (part_g_per_piece > 0),  -- grams of the part that one piece gives
    piece_step numeric CHECK (piece_step > 0),              -- pieces are counted in these steps
    piece_g numeric CHECK (piece_g > 0),                    -- weight of a piece when the target has no coefficient
    CHECK (num_nulls(part_g_per_piece, piece_step, piece_g) IN (0, 3))
) ON COMMIT DROP;

INSERT INTO ingredient_merge_codes (duplicate_code, target_code, part_g_per_piece, piece_step, piece_g) VALUES
    -- Part of a product -> the product that is bought
    ('ing_9ad2df8f9153d3dc', 'ing_e2162431045c69e8', 5, 1, 58),  -- Цедра лимона -> Лимон
    ('ing_a070cf5c1b956cc7', 'ing_e2162431045c69e8', 25, 0.5, 58),  -- Лимонный сок -> Лимон
    ('ing_ba62be6b38b69039', 'ing_7bb9e91a144d2836', 20, 0.5, 67),  -- Сок лайма -> Лайм
    ('ing_42321b4fb33f8555', 'ing_b8b8474cb00f6e86', 10, 1, 150),  -- Цедра апельсина -> Апельсин
    ('ing_7ba5eb46d9572e93', 'ing_b8b8474cb00f6e86', 30, 1, 150),  -- Апельсиновая корка -> Апельсин
    -- One product under two names
    ('ing_534b74c53dbdc472', 'ing_6406fef0f3af5aa0', NULL, NULL, NULL),  -- Перец чили свежий -> Перец чили
    ('ing_3a9926874775cbc0', 'ing_6406fef0f3af5aa0', NULL, NULL, NULL),  -- Красный чили -> Перец чили
    ('ing_2979e6299d2e3326', 'ing_66dcfd865cc753b9', NULL, NULL, NULL),  -- Зелёный острый перец -> Зелёный чили
    ('ing_0ef8cf9e439ed918', 'ing_d8b58db9a07f5d3a', NULL, NULL, NULL),  -- Рис варёный короткозёрный -> Рис варёный
    ('ing_da1256ec97e4a04f', 'ing_ed2957de9364a499', NULL, NULL, NULL),  -- Сушёный красный перец -> Перец чили сушёный
    ('ing_3d1f02da535e6426', 'ing_a7634c5219ef7424', NULL, NULL, NULL),  -- Рис короткозёрный -> Рис круглозёрный
    ('ing_5f697e464dc42431', 'ing_7a2ca3cbe75c9226', NULL, NULL, NULL),  -- Сухой имбирь молотый -> Имбирь молотый
    ('ing_cdaebe7e57318742', 'ing_1d1262b32771233f', NULL, NULL, NULL),  -- Семена аннато -> Аннато
    ('ing_a87813461cbb10fa', 'ing_f1cbbb3e68e50877', NULL, NULL, NULL),  -- Сушёный чили гуахильо -> Перец гуахильо
    ('ing_1d100490feaa291f', 'ing_f1cbbb3e68e50877', NULL, NULL, NULL),  -- Чили гуахильо -> Перец гуахильо
    ('ing_69514df64af9dd15', 'ing_867ab0cbb96ea32c', NULL, NULL, NULL),  -- Красный перец молотый -> Перец чили молотый
    ('ing_ceb01226b8c4b0eb', 'ing_f2df9b5018a53706', NULL, NULL, NULL),  -- Рисовая вермишель -> Рисовая лапша
    ('ing_5cddca7aea3107ae', 'ing_c86d8d09516f4249', NULL, NULL, NULL),  -- Тапиоковый крахмал -> Крахмал маниоковый
    ('ing_da95cc542c5b00fc', 'ing_f3cebdd1d2fd2c8b', NULL, NULL, NULL),  -- Молотые сушёные креветки -> Сушёные креветки
    ('ing_07a4b1569dfef0cc', 'ing_55254c5743c95bfa', NULL, NULL, NULL),  -- Сушёный пажитник -> Касури мети
    ('ing_2a4b997dcc32980e', 'ing_b0314b45e7dcf012', NULL, NULL, NULL),  -- Сушёный чили анчо -> Перец анчо
    ('ing_e5e7012550810901', 'ing_b0314b45e7dcf012', NULL, NULL, NULL),  -- Чили анчо -> Перец анчо
    ('ing_6ca73d503ca3dcca', 'ing_b1cb056f933d534f', NULL, NULL, NULL),  -- Подорожник -> Плантайн
    -- Variety or form the dish does not depend on -> base product
    ('ing_b0c904e07064f8b5', 'ing_5b67906812f9ce35', NULL, NULL, NULL),  -- Соль крупная -> Соль
    ('ing_74e38d82c40f131d', 'ing_9f5aff656efd8171', NULL, NULL, NULL),  -- Мука высокобелковая -> Мука
    ('ing_26ef01b95836d58c', 'ing_9f5aff656efd8171', NULL, NULL, NULL),  -- Мука обжаренная -> Мука
    ('ing_a90523acfe8a4f74', 'ing_9f5aff656efd8171', NULL, NULL, NULL),  -- Мука типа 00 -> Мука
    ('ing_00ab96be0b628922', 'ing_6362b9a2160b3580', NULL, NULL, NULL),  -- Восковой картофель -> Картофель
    ('ing_4c4c35f4a125777a', 'ing_6362b9a2160b3580', NULL, NULL, NULL),  -- Картофель варёный -> Картофель
    ('ing_8d5e6ed57b0ad34f', 'ing_6362b9a2160b3580', NULL, NULL, NULL),  -- Рассыпчатый картофель -> Картофель
    ('ing_7f70ed1a28214d33', 'ing_6362b9a2160b3580', NULL, NULL, NULL),  -- Картофель жёлтых сортов -> Картофель
    ('ing_a2a284bf36b93355', 'ing_6362b9a2160b3580', NULL, NULL, NULL),  -- Мелкий жёлтый картофель -> Картофель
    ('ing_816ad581c21510bf', 'ing_14a4780585e50d6a', NULL, NULL, NULL),  -- Масло оливковое extra virgin -> Масло оливковое
    ('ing_c60c263baab6cb14', 'ing_1ef43ec41d874f9d', NULL, NULL, NULL),  -- Морковь жёлтая -> Морковь
    ('ing_cc445fd69f68843a', 'ing_47335d405c9ace59', NULL, NULL, NULL),  -- Рис длиннозёрный -> Рис
    ('ing_a20ae6b2121a178d', 'ing_47335d405c9ace59', NULL, NULL, NULL),  -- Рис среднезёрный -> Рис
    ('ing_258cb3501e54a7c1', 'ing_4d24bc61980ba1e8', NULL, NULL, NULL),  -- Курица на кости -> Курица
    ('ing_2e38757703d24619', 'ing_1105c1e59552ebf8', NULL, NULL, NULL),  -- Красный сладкий перец -> Перец сладкий
    ('ing_50271d059ebca0f0', 'ing_1105c1e59552ebf8', NULL, NULL, NULL),  -- Красный мясистый перец -> Перец сладкий
    ('ing_9c652cbdaab3e03a', 'ing_1105c1e59552ebf8', NULL, NULL, NULL),  -- Перец сладкий зелёный -> Перец сладкий
    ('ing_ce720af62e266b3f', 'ing_b91626a52dbb2f02', NULL, NULL, NULL),  -- Сметана густая -> Сметана
    ('ing_1b02a912d21ab715', 'ing_541d4ee1e1c87f07', NULL, NULL, NULL),  -- Говядина тонкими пластами -> Говядина
    ('ing_e1e596821f7a4e2b', 'ing_541d4ee1e1c87f07', NULL, NULL, NULL),  -- Говяжий отруб -> Говядина
    ('ing_73f6ca56947af996', 'ing_541d4ee1e1c87f07', NULL, NULL, NULL),  -- Постная говядина -> Говядина
    ('ing_b34adbd4f789f8dd', 'ing_eb9af19bcc9eb5a6', NULL, NULL, NULL),  -- Корица молотая -> Корица
    ('ing_b4f49c2f3aa354c0', 'ing_3114ece82c6e01a9', NULL, NULL, NULL),  -- Сливки 20% -> Сливки
    ('ing_5b8f0dec3d533054', 'ing_806d0f13effa3beb', NULL, NULL, NULL),  -- Соус соевый светлый -> Соус соевый
    ('ing_3e149c6afc6c13a2', 'ing_1cfdd76631100fab', NULL, NULL, NULL),  -- Паприка сладкая -> Паприка
    ('ing_c1df70961ce75b27', 'ing_63a1c6d93122eee2', NULL, NULL, NULL),  -- Зира молотая -> Зира
    ('ing_5280f44639edfda8', 'ing_63a1c6d93122eee2', NULL, NULL, NULL),  -- Зира семена -> Зира
    ('ing_230dd02fa49a5a03', 'ing_d5080a8150c44fc0', NULL, NULL, NULL),  -- Белый уксус -> Уксус
    ('ing_c01137e05284d07e', 'ing_d5080a8150c44fc0', NULL, NULL, NULL),  -- Уксус 9% -> Уксус
    ('ing_c0f0a832c0797b77', 'ing_3a4cb0de7726c658', NULL, NULL, NULL),  -- Свиная грудинка со шкурой -> Свиная грудинка
    ('ing_a7bb91b82cea1b41', 'ing_5e3d8980c5685bfd', NULL, NULL, NULL),  -- Горчица средней остроты -> Горчица
    ('ing_25843a4c22415dee', 'ing_95a89b6820bca228', NULL, NULL, NULL),  -- Болгарский йогурт -> Йогурт
    ('ing_c19c9b7a867aa614', 'ing_f5ccba8460fac8cf', NULL, NULL, NULL),  -- Кардамон молотый -> Кардамон
    ('ing_8fd98a68b66c206a', 'ing_f5ccba8460fac8cf', NULL, NULL, NULL),  -- Кардамон стручки -> Кардамон
    ('ing_557dc700883ef5f1', 'ing_fbfbeef2dd1eef71', NULL, NULL, NULL),  -- Сливки 30% -> Сливки 33%
    ('ing_a85c3182ba57ac45', 'ing_cae44b44d14b6e8d', NULL, NULL, NULL),  -- Зелёные оливки -> Оливки
    ('ing_c38958520e1fd09a', 'ing_41360252fe44aaf0', NULL, NULL, NULL),  -- Овечья брынза -> Брынза
    ('ing_99e570176da5f011', 'ing_1a27b5d34b3e25a7', NULL, NULL, NULL),  -- Перец чёрный горошком -> Перец чёрный
    ('ing_1501282cfef1c9ab', 'ing_41e683c6f21c8720', NULL, NULL, NULL),  -- Арахис жареный -> Арахис
    ('ing_ff76bee750f4e0f9', 'ing_384d9b040efc72c4', NULL, NULL, NULL),  -- Уксус винный красный -> Винный уксус
    ('ing_460256bce540e500', 'ing_04a86c8257638a88', NULL, NULL, NULL),  -- Орегано сушёный -> Орегано
    ('ing_5585374d6652e15c', 'ing_14e2f4a3b901e6c8', NULL, NULL, NULL),  -- Вино красное -> Вино красное сухое
    ('ing_9bc1579da393b682', 'ing_ae0fa4e105e7005f', NULL, NULL, NULL),  -- Гвоздика молотая -> Гвоздика
    ('ing_65f9efc9c1e31eac', 'ing_ff4ab2c378956d4c', NULL, NULL, NULL),  -- Обжаренная кокосовая стружка -> Кокосовая стружка
    ('ing_a3028ac562fb1733', 'ing_2707c87f197ecffa', NULL, NULL, NULL),  -- Сахар тростниковый -> Сахар коричневый
    ('ing_fb2cc623646e8331', 'ing_2707c87f197ecffa', NULL, NULL, NULL),  -- Тёмный тростниковый сахар -> Сахар коричневый
    ('ing_a1c7619cf4b3ea35', 'ing_3ee581016ec93a5e', NULL, NULL, NULL),  -- Тмин молотый -> Тмин
    ('ing_777ff6f7cfd8ebe0', 'ing_0f5a8a31ca38b427', NULL, NULL, NULL),  -- Базилик фиолетовый -> Базилик
    ('ing_e8b2a00d0e25d291', 'ing_01594a54f269a8fb', NULL, NULL, NULL),  -- Майоран сушёный -> Майоран
    ('ing_cf4195f8edc74529', 'ing_30b94c6b1df6b7ec', NULL, NULL, NULL),  -- Сухой творог -> Творог
    ('ing_646a495745b3fbf3', 'ing_30b94c6b1df6b7ec', NULL, NULL, NULL),  -- Творог 5–9 % -> Творог
    ('ing_bce1230be14d6ea8', 'ing_30b94c6b1df6b7ec', NULL, NULL, NULL),  -- Творог твёрдый -> Творог
    ('ing_b3eb6508f04ab2c5', 'ing_38748571e07af933', NULL, NULL, NULL),  -- Перец душистый молотый -> Перец душистый
    ('ing_bab8185f9340b269', 'ing_38748571e07af933', NULL, NULL, NULL),  -- Перец душистый горошком -> Перец душистый
    ('ing_ca7d3c09f1a076a5', 'ing_eb5d8c0000cd5260', NULL, NULL, NULL),  -- Варёная ветчина -> Ветчина
    ('ing_74a328cb967ff62a', 'ing_022214fb804790b0', NULL, NULL, NULL),  -- Крахмал картофельный -> Крахмал
    ('ing_d17771c677d777e4', 'ing_f2df9b5018a53706', NULL, NULL, NULL),  -- Рисовая лапша тонкая -> Рисовая лапша
    ('ing_1e7684ea4bc89df4', 'ing_f2df9b5018a53706', NULL, NULL, NULL),  -- Рисовая лапша 5 мм -> Рисовая лапша
    ('ing_c624fd2d005c6bb7', 'ing_f2df9b5018a53706', NULL, NULL, NULL),  -- Рисовая лапша толстая -> Рисовая лапша
    ('ing_966fa72f442283a4', 'ing_c0cbec0ef9a935b0', NULL, NULL, NULL),  -- Белый хлеб -> Хлеб
    ('ing_3dba4063483a66f8', 'ing_c0cbec0ef9a935b0', NULL, NULL, NULL),  -- Чёрствый белый хлеб -> Хлеб
    ('ing_bdf1db9b5f817f87', 'ing_c0cbec0ef9a935b0', NULL, NULL, NULL),  -- Чёрствый хлеб -> Хлеб
    ('ing_5fbb19a17a6024b0', 'ing_c0cbec0ef9a935b0', NULL, NULL, NULL),  -- Деревенский хлеб -> Хлеб
    ('ing_e9c8bfefc9255c2f', 'ing_c0cbec0ef9a935b0', NULL, NULL, NULL),  -- Ломоть хлеба -> Хлеб
    ('ing_a7d6c01eb3f853d0', 'ing_c0cbec0ef9a935b0', NULL, NULL, NULL),  -- Хлеб с плотным мякишем -> Хлеб
    ('ing_d24865d3f2b211bb', 'ing_1c6d79c1acb998da', NULL, NULL, NULL),  -- Перец белый горошком -> Белый перец
    ('ing_45f61f3ca34cb2bf', 'ing_b7d7a56889d14551', NULL, NULL, NULL),  -- Бульон мясной -> Бульон
    ('ing_1b5368190e679af5', 'ing_e438611a9c0188c9', NULL, NULL, NULL),  -- Мягкий белый сыр -> Свежий белый сыр
    ('ing_ea42249c35d7e196', 'ing_e438611a9c0188c9', NULL, NULL, NULL),  -- Свежий сыр -> Свежий белый сыр
    ('ing_9f8f52ea79271af6', 'ing_3ecf5d1b43c0b82e', NULL, NULL, NULL),  -- Белый рассольный сыр -> Свежий солёный сыр
    ('ing_064622856e856edb', 'ing_3ecf5d1b43c0b82e', NULL, NULL, NULL),  -- Молодой солёный сыр -> Свежий солёный сыр
    ('ing_80802967bc55743f', 'ing_3ecf5d1b43c0b82e', NULL, NULL, NULL),  -- Солёный белый сыр -> Свежий солёный сыр
    ('ing_67599c5024edd328', 'ing_0f62d2ca445a9344', NULL, NULL, NULL),  -- Кислые яблоки -> Яблоки
    ('ing_5d9eddc858d1ddb0', 'ing_0f62d2ca445a9344', NULL, NULL, NULL),  -- Яблоки плотных кислых сортов -> Яблоки
    ('ing_976872ebec3742bf', 'ing_0f62d2ca445a9344', NULL, NULL, NULL),  -- Яблоки плотных сортов -> Яблоки
    ('ing_202677bdc77083f7', 'ing_623323ac87897db4', NULL, NULL, NULL),  -- Копчёный бекон -> Бекон
    ('ing_bb1bb96270cfc087', 'ing_a8f458fdabe86256', NULL, NULL, NULL),  -- Семена пажитника -> Пажитник
    ('ing_1c2cee314d80fed2', 'ing_a8f458fdabe86256', NULL, NULL, NULL),  -- Пажитник молотый -> Пажитник
    ('ing_d08e59585dfc92e1', 'ing_b1cb056f933d534f', NULL, NULL, NULL),  -- Плантайн зелёный -> Плантайн
    ('ing_f801371a8a34c223', 'ing_b1cb056f933d534f', NULL, NULL, NULL),  -- Плантайн спелый -> Плантайн
    ('ing_e29fa02f6b280fa3', 'ing_a9d73a4c878e53ed', NULL, NULL, NULL)  -- Хрен тёртый -> Хрен
;

CREATE TEMP TABLE ingredient_merge ON COMMIT DROP AS
SELECT d.id AS duplicate_id, t.id AS target_id, d.name AS duplicate_name, t.name AS target_name,
       c.part_g_per_piece, c.piece_step, COALESCE(t.grams_per_piece, c.piece_g) AS piece_g
FROM ingredient_merge_codes c
JOIN public.ingredients d ON d.code = c.duplicate_code
JOIN public.ingredients t ON t.code = c.target_code;

-- Zest and juice: 5 g of orange zest is one orange, not 5 g of orange.
UPDATE public.recipe_ingredients AS ri
SET qty_g = LEAST(ceil(ri.qty_g / m.part_g_per_piece / m.piece_step) * m.piece_step * m.piece_g, 999999.99)
FROM ingredient_merge m
WHERE ri.ingredient_id = m.duplicate_id
  AND m.part_g_per_piece IS NOT NULL
  AND ri.qty_g IS NOT NULL;

UPDATE public.user_pantry AS p
SET qty_g = LEAST(ceil(p.qty_g / m.part_g_per_piece / m.piece_step) * m.piece_step * m.piece_g, 999999.99)
FROM ingredient_merge m
WHERE p.ingredient_id = m.duplicate_id
  AND m.part_g_per_piece IS NOT NULL
  AND p.qty_g > 0;

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
-- coefficients it lacks. A part gives the whole product nothing of this kind.
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
      WHERE m.part_g_per_piece IS NULL
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

-- ingredient_categories has no trigger that invalidates the server's catalogue cache;
-- the other tables touched here do, this line only keeps the file self-sufficient.
UPDATE public.catalog_revision SET revision = revision + 1 WHERE singleton;
