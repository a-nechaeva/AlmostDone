# AlmostDone REST API

FastAPI-сервер приложения. Контракт: [OpenAPI 3.1](../docs/api/openapi.yaml),
базовый путь — `/api/v1`. Защищённые методы используют Bearer-токен;
для изменения данных применяются `If-Match` и `Idempotency-Key` согласно контракту.

## Запуск

Нужен Python 3.12 или новее. Из корня репозитория в Windows PowerShell:

```powershell
python -m venv server/.venv
.\server\.venv\Scripts\python.exe -m pip install -e ./engine -e "./server[postgres]"
.\server\.venv\Scripts\python.exe -m uvicorn almostdone_server.main:create_app --factory --host 127.0.0.1 --port 8000
```

Для PostgreSQL задайте `ALMOSTDONE_DATABASE_URL` и один раз примените миграцию
из корня репозитория:

```sh
psql --dbname "postgresql://USER:PASSWORD@HOST:5432/DATABASE" -v ON_ERROR_STOP=1 -f db/migrations/001_server_state.sql
```

При создании БД через актуальный `db/schema.sql` миграция уже включена.
Пользователи, сессии и данные сохраняются после перезапуска.
Без `ALMOSTDONE_DATABASE_URL` используются память
и демонстрационный каталог. Остальные настройки — в [.env.example](.env.example).

### Демо без PostgreSQL

Каталог читается прямо из дампа базы `db/seed.sql` (`ALMOSTDONE_CATALOG=../db/seed.sql`), ключ GigaChat — из `engine/.env` (в git не попадает):

```bash
cd server
set -a; . ../engine/.env; set +a
export GIGACHAT_CA_BUNDLE_FILE=../engine/certs/russian_trusted_root_ca.pem
export ALMOSTDONE_CATALOG=../db/seed.sql ALMOSTDONE_YANDEX_CLIENT_ID=de795e46d251424297db41a56379f2d3
.venv/bin/python -m uvicorn almostdone_server.main:create_app --factory --host 127.0.0.1 --port 8000
```

Телефон по USB: `adb reverse tcp:8000 tcp:8000`, приложение собирается с `-PalmostReadyApiBaseUrl=http://127.0.0.1:8000`. Пользователи и сессии в этом режиме хранятся в памяти и сбрасываются при перезапуске.

Каталог доступен через `GET /api/v1/catalog`, фото — через
`GET /api/v1/recipes/{id}/photo`. Сервер скачивает и кэширует фото;
ссылки в карточках указывают на сервер.

Docker: `docker compose up -d --build` из корня (сервер + PostgreSQL с `db/seed.sql`), ключи — в `server/.env`.
Новая БД получает схему и данные автоматически; для существующей применяется миграция выше.

После запуска:

- Swagger UI: <http://127.0.0.1:8000/docs>.
- OpenAPI: <http://127.0.0.1:8000/openapi.json>.
- Проверка процесса: <http://127.0.0.1:8000/api/v1/health>.

## Неполные данные каталога

Нерассчитываемые рецепты доступны по ID и в подборе `mode=all` с неизвестными
оценками (`null`); в `now` и `buy_1_3` они не включаются. Необязательные
ингредиенты сохраняются в карточке и предупреждениях об аллергенах, но не
участвуют в расчётах. Сервер не подставляет отсутствующие данные.
