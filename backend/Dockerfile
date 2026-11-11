# Сборка из корня репозитория: docker compose build api  (или docker build -f backend/Dockerfile .)
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    # сертификат НУЦ Минцифры для GigaChat (публичный, лежит в репозитории)
    GIGACHAT_CA_BUNDLE_FILE=/app/engine/certs/russian_trusted_root_ca.pem

WORKDIR /app
COPY engine/ engine/
COPY backend/pyproject.toml backend/
COPY backend/app/ backend/app/
# дамп нужен только для режима без базы (если DATABASE_URL не задан)
COPY db/seed.sql db/seed.sql

RUN pip install ./engine ./backend

WORKDIR /app/backend
EXPOSE 8000
CMD ["uvicorn", "--factory", "app.main:create_app", "--host", "0.0.0.0", "--port", "8000"]
