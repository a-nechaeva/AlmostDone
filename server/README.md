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

После запуска:

- Swagger UI: <http://127.0.0.1:8000/docs>.
- OpenAPI JSON: <http://127.0.0.1:8000/openapi.json>.
- Проверка процесса: <http://127.0.0.1:8000/api/v1/health>.
