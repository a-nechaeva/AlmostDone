# AlmostDone REST API

FastAPI-сервер приложения. Контракт: [OpenAPI 3.1](../docs/api/openapi.yaml),
базовый путь — `/api/v1`. Защищённые методы используют Bearer-токен;
для изменения данных применяются `If-Match` и `Idempotency-Key` согласно контракту.

## Запуск через Docker

На Ubuntu нужны Docker Engine с запущенным сервисом и плагин Docker Compose
(команда `docker compose`). Все команды ниже выполняются из корня репозитория.
Python и PostgreSQL на хосте устанавливать не нужно.

При первом запуске создайте файл настроек:

```bash
cp server/.env.example server/.env
```

В `server/.env` заполните `ALMOSTDONE_YANDEX_CLIENT_ID` для входа через Яндекс,
а для распознавания фото — `GIGACHAT_CREDENTIALS` и `GIGACHAT_MODEL`.
Без этих настроек соответствующие функции недоступны.
Адрес БД и путь сертификата внутри контейнера уже задаёт Compose.

Соберите и запустите сервер с PostgreSQL:

```bash
docker compose up -d --build
```

Новая БД получает схему и данные из `db/schema.sql` и `db/seed.sql`.
Для существующей БД сервис `migrate` автоматически применяет недостающие
миграции перед запуском API. При ошибке миграции API не запускается.
Пользователи, сессии, кладовая и избранное хранятся в томе PostgreSQL
и сохраняются после перезапуска контейнеров.

### Проверка запуска

```bash
docker compose ps -a
docker compose logs migrate
docker compose logs --tail=100 api
curl --fail http://localhost:8000/api/v1/health
```

Ожидается: `db` — `healthy`, `migrate` — `Exited (0)`, `api` — `Up`.
В логах мигратора — `Migrations ready`, API — `Application startup complete`.
Healthcheck проверяет процесс; работу БД дополнительно проверьте через приложение:
войдите, добавьте продукт и рецепт в избранное, выполните
`docker compose restart api` и убедитесь, что вход и данные сохранились.

- Swagger UI: <http://localhost:8000/docs>.
- OpenAPI: <http://localhost:8000/openapi.json>.
- Проверка процесса: <http://localhost:8000/api/v1/health>.

### Обновление и остановка

После получения обновлений репозитория:

```bash
docker compose up -d --build
```

Повторная проверка миграций (уже применённые версии пропускаются):

```bash
docker compose run --rm migrate
```

Остановка с сохранением базы:

```bash
docker compose down
```

Не добавляйте `-v`, если хотите сохранить данные: `docker compose down -v`
удаляет том с базой.

### Подключение Android

Телефон по USB: `adb reverse tcp:8000 tcp:8000`.
Приложение собирается с `-PalmostReadyApiBaseUrl=http://127.0.0.1:8000`.

Каталог доступен через `GET /api/v1/catalog`, фото — через
`GET /api/v1/recipes/{id}/photo`. Сервер скачивает и кэширует фото;
ссылки в карточках указывают на сервер.

## Неполные данные каталога

Нерассчитываемые рецепты доступны по ID и в подборе `mode=all` с неизвестными
оценками (`null`); в `now` и `buy_1_3` они не включаются. Необязательные
ингредиенты сохраняются в карточке и предупреждениях об аллергенах, но не
участвуют в расчётах. Сервер не подставляет отсутствующие данные.
