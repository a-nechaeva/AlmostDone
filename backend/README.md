# Сервер «Почти готово»

FastAPI поверх движка [`engine/`](../engine/README.md). Пути и форматы ответов — из контракта
[`docs/api/openapi.yaml`](../docs/api/openapi.yaml), префикс `/api/v1`. Тесты проверяют каждый ответ
по JSON-схемам контракта.

## Запуск

### Без Docker (быстрее всего, для демо на ноутбуке)

Каталог читается прямо из `db/seed.sql` — база не нужна.

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -e ../engine -e '.[dev]'
cp .env.example .env            # вписать ключ GigaChat — нужен только для распознавания
.venv/bin/uvicorn --factory app.main:create_app --host 0.0.0.0 --port 8000
```

### Docker: сервер + PostgreSQL 18

```bash
cp backend/.env.example backend/.env   # из корня репозитория
docker compose up -d --build
docker compose logs -f api
```

При первом запуске PostgreSQL сам загружает `db/seed.sql` (около 10–20 секунд). Пересоздать базу
с нуля: `docker compose down -v && docker compose up -d --build`.

### Проверка

- http://localhost:8000/api/v1/health → `{"status": "ok", "api_version": "v1"}`
- http://localhost:8000/api/v1/debug/catalog — откуда загружен каталог и сколько в нём рецептов
- http://localhost:8000/docs — Swagger: все запросы можно отправить из браузера

```bash
.venv/bin/pytest -q             # тесты (из папки backend)
```

## Что реализовано

| Метод | Путь | Что делает |
| --- | --- | --- |
| GET | `/health` | Проверка процесса |
| GET | `/me/state` | Версия состояния и каталога |
| GET | `/allergens` | Справочник аллергенов (коды + русские названия) |
| GET | `/ingredients?q=малако&limit=20` | Поиск по названию и синонимам, с опечатками |
| GET | `/me/pantry` | Кладовка |
| POST | `/me/pantry/add` | Добавить продукт (`quantity: null` — «есть, количество не указано») |
| PUT | `/me/pantry/{ingredient_id}` | Установить количество (`0` удаляет) |
| DELETE | `/me/pantry/{ingredient_id}` | Удалить продукт |
| POST | `/me/pantry/purchased` | Добавить купленное |
| POST | `/recommendations` | Подбор блюд: снимок + первая страница карточек |
| GET | `/recommendations/{snapshot_id}?cursor=` | Следующая страница снимка |
| GET | `/recommendations/{snapshot_id}/graph` | Граф всего снимка: `home` → `purchase` → `recipe` |
| GET | `/recipes/{recipe_id}?servings=2&exclude_allergens=milk` | Рецепт: состав «есть / не хватает», шаги, что докупить |
| POST | `/recommendations/single-purchase` | Лучшие одиночные покупки в пределах бюджета |
| POST | `/recommendations/budget` | План покупок под бюджет |
| POST | `/recognitions` | Фото чека или продуктов (multipart: `kind`, `file`) → распознанные строки |
| GET | `/recognitions/{recognition_id}` | Результат распознавания |
| POST | `/recognition-imports` | Добавить подтверждённые строки в кладовку |

### Упрощения демо-версии (отличия от контракта)

- **Без авторизации.** Один пользователь `demo`; заголовок `Authorization` можно не передавать.
  `/auth/*`, `/me` (профиль), избранное и `/dietary-options` пока не реализованы.
- **Всё в памяти процесса.** Кладовка, снимки и распознавания сбрасываются при перезапуске сервера.
  При старте в кладовку кладётся демо-набор из 20 продуктов (`DEMO_PANTRY=false` — пустая кладовка).
- **`If-Match` и `Idempotency-Key` не обязательны** (428 не возвращается). `ETag` в ответах кладовки есть.
- **Распознавание синхронное:** `POST /recognitions` отвечает через 5–20 секунд сразу со `status: succeeded`
  или `failed`. Опрашивать `GET /recognitions/{id}` не нужно, но можно.
- **Скрытых блюд нет** (`visibility: hidden` → пустой список): ограничений профиля пока нет.
  Фильтр `exclude_allergens` работает.
- **Единицы:** граммы и миллилитры взаимозаменяемы (1:1) — «молоко 1 л» из чека сохраняется как 1000 г.
  Штуки (`pcs`) — только у продуктов с весом штуки.

## Для Android (Захар, Аня)

- **Адрес сервера:**
  - эмулятор → `http://10.0.2.2:8000/api/v1/`;
  - телефон → `http://<IP ноутбука>:8000/api/v1/` (телефон и ноутбук в одной сети; IP — `ipconfig getifaddr en0` на macOS).
- **HTTP без TLS:** Android по умолчанию запрещает. Для демо: `android:usesCleartextTraffic="true"` в
  `AndroidManifest.xml` (или `network_security_config` с адресом ноутбука) и разрешение `INTERNET`.
- **Сценарий экранов:**
  1. Кладовка: `GET /me/pantry`, поиск — `GET /ingredients?q=`, добавление — `POST /me/pantry/add`.
  2. Блюда: `POST /recommendations` → карточки; граф — `GET /recommendations/{snapshot_id}/graph`.
  3. Рецепт: `GET /recipes/{id}?servings=<из ответа подбора>`.
  4. Покупки: `POST /recommendations/single-purchase` и `/budget`.
  5. Фото: `POST /recognitions` → экран подтверждения → `POST /recognition-imports` → снова подбор.
- **Примеры ответов** — в Swagger (`/docs`, кнопка «Try it out») и в `docs/api/examples.json`.

## Как устроено

```
app/
  config.py           настройки из окружения и backend/.env
  catalog_source.py   каталог: PostgreSQL (engine/sql/catalog.sql) или блоки COPY из db/seed.sql
  state.py            демо-пользователь: кладовка, снимки, распознавания (в памяти)
  contract.py         результаты движка → форматы контракта (Money в копейках, ShoppingItem, RecipeCard, Graph)
  main.py             эндпоинты, ошибки в формате контракта
tests/test_api.py     сценарии API на реальном seed.sql, ответы сверяются со схемами openapi.yaml
```
