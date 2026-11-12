FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    ALMOSTDONE_YANDEX_CLIENT_ID=de795e46d251424297db41a56379f2d3 \
    PIP_NO_CACHE_DIR=1 \
    GIGACHAT_CA_BUNDLE_FILE=/app/engine/certs/russian_trusted_root_ca.pem

WORKDIR /app
COPY engine/pyproject.toml engine/pyproject.toml
COPY engine/dishgraph/ engine/dishgraph/
COPY engine/certs/ engine/certs/
COPY engine/data/ engine/data/
COPY engine/sql/ engine/sql/
COPY server/pyproject.toml server/pyproject.toml
COPY server/src/ server/src/
COPY server/data/ server/data/
COPY docs/api/openapi.yaml docs/api/openapi.yaml
COPY db/migrations/ db/migrations/

RUN pip install "./engine[llm]" -e "./server[postgres]"

ARG ALMOSTDONE_DEPLOY_REVISION
ENV ALMOSTDONE_DEPLOY_REVISION=${ALMOSTDONE_DEPLOY_REVISION}

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/v1/health/ready', timeout=4)"
CMD ["uvicorn", "almostdone_server.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000"]
