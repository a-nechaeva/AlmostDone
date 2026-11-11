# Сборка из корня репозитория: docker compose build api  (или docker build -f server/Dockerfile .)
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    # сертификат НУЦ Минцифры для GigaChat (публичный, лежит в репозитории)
    GIGACHAT_CA_BUNDLE_FILE=/app/engine/certs/russian_trusted_root_ca.pem

WORKDIR /app
COPY engine/ engine/
COPY server/ server/
# контракт читается из docs/api/openapi.yaml относительно корня репозитория
COPY docs/api/openapi.yaml docs/api/openapi.yaml
# дамп — для запуска без базы: ALMOSTDONE_CATALOG=/app/db/seed.sql
COPY db/seed.sql db/seed.sql
COPY db/migrations/ db/migrations/

# editable-установка сервера: пути к контракту и данным считаются от /app, как в репозитории
RUN pip install "./engine[llm]" -e "./server[postgres]"

EXPOSE 8000
CMD ["uvicorn", "almostdone_server.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000"]
