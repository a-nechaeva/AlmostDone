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

Для PostgreSQL задайте `ALMOSTDONE_DATABASE_URL` и примените миграцию
`001_server_state` по [инструкции БД](../db/README.md). Пользователи, сессии и
данные сохраняются после перезапуска. Без этой переменной используются память
и демонстрационный каталог. Остальные настройки — в [.env.example](.env.example).

- Swagger UI: <http://127.0.0.1:8000/docs>.
- OpenAPI: <http://127.0.0.1:8000/openapi.json>.
- Проверка процесса: <http://127.0.0.1:8000/api/v1/health>.

## Неполные данные каталога

Нерассчитываемые рецепты доступны по ID и в подборе `mode=all` с неизвестными
оценками (`null`); в `now` и `buy_1_3` они не включаются. Необязательные
ингредиенты сохраняются в карточке и предупреждениях об аллергенах, но не
участвуют в расчётах. Сервер не подставляет отсутствующие данные.
