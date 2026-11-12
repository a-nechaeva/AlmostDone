# AlmostDone REST API

FastAPI-сервер приложения. Контракт: [OpenAPI 3.1](../docs/api/openapi.yaml),
базовый путь — `/api/v1`. Защищённые методы используют Bearer-токен;
для изменения данных применяются `If-Match` и `Idempotency-Key` согласно контракту.

## Запуск через Docker Compose

Нужны запущенный Docker Engine (или Docker Desktop) и Docker Compose.
Все команды выполняются из корня репозитория.

При первом запуске создайте настройки (существующий `.env` не перезаписывайте):

```bash
cp server/.env.example server/.env
```

Для распознавания фото заполните `GIGACHAT_CREDENTIALS` и `GIGACHAT_MODEL`
в `server/.env`. Без ключей распознавание недоступно. Client ID Яндекса уже
задан в Dockerfile. Адрес PostgreSQL и путь сертификата задаёт Compose.

Сборка и запуск API вместе с PostgreSQL:

```bash
docker compose -f server/docker-compose.yml up -d --build
```

Новая БД получает схему и данные из `db/schema.sql` и `db/seed.sql`.
Сервис `migrate` автоматически применяет недостающие миграции перед запуском API.
При ошибке миграции API не запускается. Пользователи, сессии, кладовая и избранное
хранятся в томе PostgreSQL и сохраняются после перезапуска контейнеров.

### Проверка запуска

```bash
docker compose -f server/docker-compose.yml ps -a
docker compose -f server/docker-compose.yml logs migrate
docker compose -f server/docker-compose.yml logs --tail=100 api
curl --fail http://localhost:8000/api/v1/health
curl --fail http://localhost:8000/api/v1/health/ready
```

Ожидается: `db` — `healthy`, `migrate` — `Exited (0)`, `api` — `Up`.
В логах мигратора — `Migrations ready`, API — `Application startup complete`.
`/health` проверяет только процесс. Docker healthcheck вызывает `/health/ready`:
он проверяет подключение к БД, доступность таблиц, применённые миграции,
загруженный каталог и движок dishgraph. При отказе обязательной зависимости
возвращается HTTP 503, а контейнер после неудачных проверок становится unhealthy.
Яндекс и распознавание показываются как `configured` или `disabled`;
это состояние настройки, а не подтверждение доступности внешнего сервиса.
Проверки не вызывают Яндекс и GigaChat и не изменяют данные.

Запись и сохранение данных дополнительно проверьте через приложение:
войдите, добавьте продукт и рецепт в избранное, выполните
`docker compose -f server/docker-compose.yml restart api` и убедитесь, что вход и данные сохранились.

- Swagger UI: <http://localhost:8000/docs>.
- OpenAPI: <http://localhost:8000/openapi.json>.
- Проверка процесса: <http://localhost:8000/api/v1/health>.
- Проверка готовности: <http://localhost:8000/api/v1/health/ready>.

### Обновление и остановка

После получения обновлений репозитория:

```bash
docker compose -f server/docker-compose.yml up -d --build
```

Повторная проверка миграций (уже применённые версии пропускаются):

```bash
docker compose -f server/docker-compose.yml run --rm migrate
```

Остановка с сохранением базы:

```bash
docker compose -f server/docker-compose.yml down
```

Не добавляйте `-v`, если хотите сохранить данные: `docker compose -f server/docker-compose.yml down -v`
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
