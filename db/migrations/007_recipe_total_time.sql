-- The recipe card shows recipes.cook_time_min as "N мин всего" and the dish filter
-- compares it with the time the user has. The value was far below the recipe's
-- own steps: in 185 of 368 fully timed recipes the step minutes added up to more
-- than twice cook_time_min (Хинкали: 15 against 140).
--
-- From now on cook_time_min of a bundled recipe is the sum of its step minutes.
-- Before the sum is taken, two kinds of step durations are corrected:
--   1. 40 serving and assembly steps had no duration at all;
--   2. 61 steps prescribe a wait in their text (marinate overnight, chill four
--      hours) that the duration did not include. The shortest wait named in the
--      text is added; waits called optional ("лучше на ночь") are not.
-- A step is changed only if the recipe title and the old duration still match.

CREATE TEMP TABLE step_minutes (
    recipe_id integer NOT NULL,
    title text NOT NULL,
    step_no integer NOT NULL,
    old_minutes integer,
    new_minutes integer NOT NULL CHECK (new_minutes > 0),
    PRIMARY KEY (recipe_id, step_no)
) ON COMMIT DROP;

INSERT INTO step_minutes (recipe_id, title, step_no, old_minutes, new_minutes) VALUES
    -- 1. Steps without a duration
    (11, 'Паэлья валенсиана', 4, NULL, 2),
    (13, 'Мусака', 5, NULL, 10),
    (14, 'Хориатики', 2, NULL, 5),
    (14, 'Хориатики', 3, NULL, 2),
    (16, 'Бань ми', 4, NULL, 5),
    (23, 'Кацудон', 3, NULL, 2),
    (23, 'Кацудон', 6, NULL, 1),
    (26, 'Тирамису', 6, NULL, 1),
    (30, 'Ломо сальтадо', 5, NULL, 2),
    (35, 'Кезешпецле', 5, NULL, 1),
    (37, 'Пибимпап', 5, NULL, 5),
    (38, 'Кимчхи чиге', 5, NULL, 1),
    (41, 'Сёю рамен', 6, NULL, 3),
    (42, 'Пероги руске', 6, NULL, 2),
    (43, 'Журек', 5, NULL, 2),
    (46, 'Аматричана', 5, NULL, 2),
    (47, 'Шакшука', 5, NULL, 1),
    (48, 'Хумус', 5, NULL, 2),
    (49, 'Фейжоада', 6, NULL, 3),
    (52, 'Гюдон', 5, NULL, 2),
    (53, 'Солянка мясная сборная', 6, NULL, 2),
    (57, 'Лангош', 6, NULL, 2),
    (60, 'Венский шницель', 3, NULL, 1),
    (76, 'Кушари', 6, NULL, 3),
    (77, 'Фуль медамес', 5, NULL, 3),
    (93, 'Посоле рохо', 6, NULL, 5),
    (95, 'Чапли кебаб', 5, NULL, 2),
    (97, 'Роти чанай', 6, NULL, 1),
    (99, 'Поффертьес', 6, NULL, 1),
    (100, 'Доро уот', 6, NULL, 1),
    (105, 'Аки с солёной рыбой', 5, NULL, 1),
    (107, 'Суйя', 5, NULL, 2),
    (108, 'Арепас', 6, NULL, 3),
    (117, 'Пататас бравас', 6, NULL, 1),
    (119, 'Дал бхат', 6, NULL, 2),
    (122, 'Чевапи', 6, NULL, 2),
    (124, 'Фрикаделлер', 6, NULL, 1),
    (125, 'Смёрребрёд', 5, NULL, 1),
    (130, 'Лохикейтто', 6, NULL, 2),
    (140, 'Сырное фондю', 6, NULL, 1),
    -- 2. Steps whose text prescribes a longer wait
    (26, 'Тирамису', 5, 5, 365),
    (27, 'Гаспачо', 4, 5, 125),
    (65, 'Чимичурри', 4, 5, 125),
    (141, 'Рёшти', 1, 20, 500),
    (143, 'Спас', 1, 27, 507),
    (144, 'Шах-плов', 1, 20, 80),
    (151, 'Эмпанадас-де-пино', 3, 10, 180),
    (154, 'Сальтеньяс', 3, 15, 240),
    (160, 'Мансаф', 1, 25, 265),
    (171, 'Кама', 5, 5, 65),
    (182, 'Ньяма-чома', 1, 15, 75),
    (187, 'Ясса с курицей', 1, 20, 260),
    (198, 'Ламингтоны', 4, 20, 480),
    (198, 'Ламингтоны', 7, 30, 90),
    (211, 'Таджикский оши палав', 1, 15, 75),
    (212, 'Кабули палав', 1, 15, 135),
    (228, 'Кролик по-мальтийски', 1, 20, 1460),
    (234, 'Доминиканский санкочо', 1, 20, 80),
    (242, 'Копчёная шейка с бобами', 1, 15, 240),
    (259, 'Курица пири-пири', 4, 12, 492),
    (265, 'Накатамаль', 1, 20, 500),
    (291, 'Масала доса', 1, 15, 360),
    (291, 'Масала доса', 3, 20, 480),
    (300, 'Фабада астурийская', 1, 10, 720),
    (300, 'Фабада астурийская', 6, 8, 35),
    (309, 'Шварцвальдский торт', 7, 20, 260),
    (310, 'Раздёрганная свинина', 3, 10, 480),
    (311, 'Пирог с лаймом', 7, 15, 255),
    (312, 'Бун ча', 1, 25, 85),
    (315, 'Самгетан', 1, 10, 120),
    (318, 'Бигос', 6, 65, 1505),
    (318, 'Бигос', 7, 65, 1505),
    (323, 'Кауса лименья', 7, 12, 132),
    (328, 'Сатэ аям', 2, 12, 120),
    (333, 'Сациви', 7, 20, 380),
    (353, 'Рисаламанде', 6, 10, 190),
    (354, 'Эртенсуп', 6, 15, 480),
    (355, 'Биттербаллен', 4, 15, 255),
    (365, 'Лече флан', 7, 45, 285),
    (366, 'Ынджера', 2, 10, 4320),
    (366, 'Ынджера', 5, 15, 135),
    (388, 'Таратор', 7, 8, 68),
    (390, 'Хопперы', 3, 10, 480),
    (392, 'Сель роти', 1, 12, 492),
    (394, 'Халим', 1, 15, 495),
    (399, 'Мелктерт', 7, 12, 192),
    (412, 'Мухаммара', 7, 8, 68),
    (420, 'Скир с ягодами', 5, 10, 720),
    (420, 'Скир с ягодами', 6, 15, 375),
    (421, 'Исландский чёрный хлеб', 7, 20, 1460),
    (442, 'Эквадорский севиче', 7, 8, 68),
    (451, 'Кохуке', 5, 15, 135),
    (457, 'Краньская колбаса', 4, 10, 1440),
    (457, 'Краньская колбаса', 6, 15, 135),
    (461, 'Пастрмалия', 1, 20, 140),
    (472, 'Оманская халва', 7, 15, 375),
    (474, 'Зурбиан', 1, 20, 140),
    (475, 'Фахса', 1, 20, 360),
    (483, 'Витумбуа', 3, 20, 240),
    (486, 'Клефтико', 3, 15, 240),
    (497, 'Чакка', 3, 10, 1440);

UPDATE public.recipe_steps s
SET duration_min = m.new_minutes
FROM step_minutes m
JOIN public.recipes r ON r.id = m.recipe_id AND r.title = m.title AND r.author_id IS NULL
WHERE s.recipe_id = m.recipe_id
  AND s.step_no = m.step_no
  AND s.duration_min IS NOT DISTINCT FROM m.old_minutes;

-- Personal recipes keep the time their author entered. A bundled recipe with an
-- untimed step keeps its old value, because the sum would be incomplete.
UPDATE public.recipes r
SET cook_time_min = t.total
FROM (SELECT recipe_id, sum(duration_min)::integer AS total
      FROM public.recipe_steps
      GROUP BY recipe_id
      HAVING bool_and(duration_min IS NOT NULL)) t
WHERE r.id = t.recipe_id
  AND r.author_id IS NULL
  AND r.cook_time_min <> t.total;
