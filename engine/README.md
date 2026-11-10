# dishgraph — движок графа достижимых блюд

Чистая логика на Python без внешних зависимостей: по кладовке пользователя строит блюда уровней 0–3,
граф «Дома → Купить X → блюдо», считает стоимость докупки целыми упаковками, время, КБЖУ, аллергены
и подсказывает, что докупить. Формат данных совпадает со схемой БД Карины (`db/schema.sql`).

Ответственная: Рината. Вызывается из FastAPI (Диана), данные — из PostgreSQL (Карина).
Требования к приложению — в [docs/task.md](../docs/task.md).

## Запуск

```bash
cd engine
python3 -m venv .venv
.venv/bin/pip install -e '.[dev]'
.venv/bin/pytest -q                       # тесты
.venv/bin/python -m dishgraph.demo        # пример на тестовых данных
.venv/bin/python -m dishgraph.demo --json # + JSON графа
```

## Как вызывать (для Дианы)

```python
from dishgraph import (load_catalog, catalog_from_dict, reachable_dishes, dish_option,
                       build_graph, best_single_purchases, best_purchases, SearchIndex)

catalog = catalog_from_dict(row["catalog"])   # один раз при старте, см. «Загрузка из БД»

pantry = {"egg": 110, "milk": None}            # user_pantry: граммы или None («есть, хватает»)
options = reachable_dishes(
    pantry, catalog,
    max_missing=3,                             # сколько можно докупить
    equipment={"stove", "microwave"},          # техника пользователя; None — не фильтровать
    hidden={"12", "40"},                       # id рецептов с is_hidden = true из user_recipe_visibility
    exclude_allergens=set(),                   # для экрана фильтров; аллергены профиля уже в hidden
    max_minutes=30, max_kcal=600,              # необязательно, ккал на порцию
)

[o.to_dict(catalog) for o in options]                          # список блюд
build_graph(options, catalog)                                  # граф {nodes, edges}
[p.to_dict(catalog) for p in best_single_purchases(options, catalog)]
best_purchases(options, catalog, budget=500).to_dict(catalog)  # план покупок на бюджет

# «Скрытые блюда»: метрики без фильтров + причины из user_recipe_visibility
dish_option(catalog.recipe("12"), pantry, catalog).to_dict(catalog)

# Автодополнение для GET /ingredients/search?q=...
index = SearchIndex(catalog)                                   # один раз при старте, вместе с каталогом
[h.to_dict() for h in index.search("малако", limit=10)]
# → [{"code": "milk", "name": "Молоко 2,5%", "matched": "Молоко 2,5%", "score": 0.6}]
```

Все `to_dict` / `build_graph` возвращают обычные dict/list — их можно сразу отдавать из эндпоинта.

### Автодополнение

[search.py](dishgraph/search.py) ищет по названиям и синонимам (`aliases`). Регистр, пробелы по краям
и «ё»/«е» не важны. Оценка совпадения:

| Оценка | Когда | Пример |
| --- | --- | --- |
| 1.0 | Запрос — начало названия или синонима | «яйц» → Яйцо, «картошк» → Картофель |
| 0.9 | Запрос — начало другого слова в названии | «твёрд» → Сыр твёрдый |
| 0.5–0.7 | До 2 опечаток в начале названия, запрос от 4 букв; чем меньше правок до всего слова, тем выше | «малако» → Молоко (0.6) выше, чем → Макароны (0.5) |
| 0.5–1 | Триграммное сходство со словом (как `pg_trgm`) | |

Результаты с оценкой ниже 0.5 отбрасываются; сортировка — по оценке, затем короткие названия выше.
Один поиск на тестовых данных (36 ингредиентов с синонимами) занимает около 2 мс; на 150 ингредиентах — порядка 10 мс.

### Разделение с БД

| База (`user_recipe_visibility`) | Движок |
| --- | --- |
| Какие блюда скрыть и почему: аллергены профиля, диеты и столы Певзнера (по категориям продуктов, аллергенам — например, «без глютена», — и способам готовки) | Подбор блюд, уровни 0–3 |
| `skip_optional` — что «по вкусу» лучше не класть | Цена докупки упаковками, КБЖУ, время |
| | Граф, лучшая покупка, план под бюджет |
| | Автодополнение ингредиентов |

## Загрузка из БД

[sql/catalog.sql](sql/catalog.sql) собирает весь каталог (без личных рецептов) одним JSON-документом
в формате `catalog_from_dict`:

```python
row = conn.execute(open("engine/sql/catalog.sql").read()).fetchone()
catalog = catalog_from_dict(row["catalog"])
```

Проверено: тестовые данные, загруженные в PostgreSQL 16 по схеме, дают движку те же блюда, уровни,
цены, КБЖУ, граф и план покупок, что и `data/fixtures.json`.

## Формат данных

См. `data/fixtures.json` — пока БД нет, движок работает на этом файле. Поля = колонки схемы.

- **Ингредиент:** `code`, `name`, `is_staple`, `package_g`, `package_price`, `kcal`/`protein`/`fat`/`carbs`
  на 100 г, `allergens` (коды), `aliases`, `display_unit` (`g`/`ml`/`pcs`), `grams_per_piece`.
- **Рецепт:** `id`, `title`, `servings`, `cook_time_min`, `needs_microwave`/`needs_stove`/`needs_oven`,
  `steps`, `description`, `items` — список `{code, qty_g, is_optional}`. Граммы — на весь рецепт.
- **`is_staple`** (соль, вода, масло, перец, сахар) — «есть всегда»: не докупаем, но в КБЖУ и цене порции считаем.
- **`is_optional`** — «по вкусу»: не докупаем и не считаем в КБЖУ, аллергенах и цене порции.
- **Коды аллергенов:** `gluten`, `milk`, `eggs`, `fish`, `crustaceans`, `molluscs`, `peanuts`, `nuts`,
  `soy`, `sesame`, `mustard`, `celery`, `lupin`, `sulphites` (14 основных аллергенов ЕС).

Загрузчик повторяет ограничения схемы: формат кода, БЖУ ≤ 100 г на 100 г, ккал 0–900, вес штуки для `pcs`,
неизвестные или повторяющиеся ингредиенты в рецепте, рецепт без обязательных ингредиентов → `CatalogError`.

## Граф (для Захара и Ани)

```json
{
  "nodes": [
    {"id": "home", "type": "home", "level": 0},
    {"id": "buy:milk", "type": "purchase", "level": 1,
     "items": [{"code": "milk", "name": "Молоко 2,5%", "packs": 1, "cost": 95.0}], "cost": 95, "dish_count": 2},
    {"id": "dish:omelette", "type": "dish", "level": 1, "recipe_id": "omelette", "title": "Омлет",
     "cook_time_min": 10, "equipment": ["stove"], "kcal": 273.5, "protein": 15.4, "fat": 22.1, "carbs": 3.2,
     "buy_cost": 95, "portion_cost": 41.0, "allergens": ["eggs", "milk"]}
  ],
  "edges": [
    {"from": "home", "to": "buy:milk",
     "add": [{"code": "milk", "name": "Молоко 2,5%", "packs": 1, "cost": 95.0}], "add_cost": 95},
    {"from": "buy:milk", "to": "dish:omelette"}
  ]
}
```

- `level` — номер колонки при раскладке (0 — дома и готовые блюда, 1–3 — сколько докупить).
- Узлы покупок связаны цепочкой: `buy:milk → buy:flour+milk` с подписью `add` = «+ мука».
  У узла может быть несколько родителей (`buy:egg` и `buy:milk` → `buy:egg+milk`).
- Каждый узел достижим из `home` (проверяется тестами).

## Как считаются метрики

- **Недостающее** — обязательные ингредиенты, которых нет в кладовке или меньше, чем нужно
  (продукт без количества считается достаточным).
- **buy_cost** — `Σ ceil(не хватает г / package_g) × package_price` (`Catalog.pack_cost`).
- **portion_cost** — `Σ(qty_g / package_g × package_price) / servings` по обязательным ингредиентам.
- **КБЖУ на порцию** — `Σ(qty_g / 100 × значение на 100 г) / servings`, как `recipe_nutrition` в БД.
- **best_purchases** — жадный алгоритм: на каждом шаге докупаем то, что даёт больше всего новых блюд
  на рубль; уже купленные упаковки учитываются для следующих блюд.

## Дальше

- [ ] День 3: распознавание чека через LLM → `recognize_products(image, source) -> [{raw_name, code, confidence}]`.
- [ ] День 4: подобрать демо-кладовку, при которой граф выглядит лучше всего.
