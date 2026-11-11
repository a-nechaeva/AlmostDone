# AlmostDone REST API

Контракт API: [OpenAPI 3.1](../docs/api/openapi.yaml).

Базовый путь — `/api/v1`. Контракт описывает авторизацию, профиль, продукты пользователя, избранное, каталог, рекомендации и распознавание.

Для защищённых методов используется `Authorization: Bearer <access_token>`. Заголовки `If-Match` и `Idempotency-Key` передаются для операций, где они указаны в контракте.

## Запуск

Нужен Python 3.12 или новее. Пример для Windows PowerShell из корня репозитория:

```powershell
python -m venv server/.venv
.\server\.venv\Scripts\python.exe -m pip install -e ./engine -e "./server[postgres]"
.\server\.venv\Scripts\python.exe -m uvicorn almostdone_server.main:create_app --factory --host 127.0.0.1 --port 8000
```

Без `ALMOSTDONE_DATABASE_URL` сервер использует данные в памяти и демонстрационный каталог. Для подключения к существующей PostgreSQL задайте эту переменную окружения перед запуском. Остальные параметры перечислены в [.env.example](.env.example).

### Демо на ноутбуке без PostgreSQL (macOS)

Каталог читается прямо из дампа базы `db/seed.sql` (`ALMOSTDONE_CATALOG=../db/seed.sql`), ключ GigaChat — из `engine/.env` (в git не попадает):

```bash
cd server
set -a; . ../engine/.env; set +a
export GIGACHAT_CA_BUNDLE_FILE=../engine/certs/russian_trusted_root_ca.pem
export ALMOSTDONE_CATALOG=../db/seed.sql ALMOSTDONE_YANDEX_CLIENT_ID=de795e46d251424297db41a56379f2d3
.venv/bin/python -m uvicorn almostdone_server.main:create_app --factory --host 127.0.0.1 --port 8000
```

Телефон по USB: `adb reverse tcp:8000 tcp:8000`, приложение собирается с `-PalmostReadyApiBaseUrl=http://127.0.0.1:8000`. Пользователи и сессии в этом режиме хранятся в памяти и сбрасываются при перезапуске.

Приложение берёт каталог из `GET /api/v1/catalog`, а фото рецептов — из `GET /api/v1/recipes/{id}/photo`: сайт с фото стоит за Cloudflare и из мобильной сети недоступен, поэтому сервер скачивает фото сам и кэширует во временной папке. Все `photo_url` в ответах API указывают на этот адрес.

Docker: `docker compose up -d --build` из корня (сервер + PostgreSQL с `db/seed.sql`), ключи — в `server/.env`.

После запуска:

- Swagger UI: <http://127.0.0.1:8000/docs>.
- OpenAPI JSON: <http://127.0.0.1:8000/openapi.json>.
- Проверка процесса: <http://127.0.0.1:8000/api/v1/health>.
