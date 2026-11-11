import json
from pathlib import Path

import pytest
import yaml
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

from app.config import REPO_ROOT, Settings
from app.main import create_app
from dishgraph.recognition import FakeProvider

CONTRACT = yaml.safe_load((REPO_ROOT / "docs" / "api" / "openapi.yaml").read_text(encoding="utf-8"))
_REGISTRY = Registry().with_resource("contract", DRAFT202012.create_resource(CONTRACT))

JPEG = b"\xff\xd8\xff\xe0" + b"\0" * 100

# Ответ модели для распознавания чека в тестах (реальные коды из seed.sql подставляются ниже)
RECEIPT_ITEMS = [("ЯЙЦО КУР.С1 10ШТ", "Яйцо куриное", {"value": 10, "unit": "pcs"}),
                 ("МОЛОКО 2,5% 1Л", "Молоко", {"value": 1, "unit": "l"})]


def assert_contract(body, schema_name):
    """Ответ сервера соответствует схеме из docs/api/openapi.yaml."""
    schema = {"$ref": f"contract#/components/schemas/{schema_name}"}
    errors = sorted(Draft202012Validator(schema, registry=_REGISTRY).iter_errors(body), key=str)
    assert not errors, f"{schema_name}: " + "; ".join(f"{list(e.absolute_path)}: {e.message}" for e in errors[:5])


def make_client(provider_factory=None, demo_pantry=True):
    settings = Settings(
        database_url=None,
        seed_path=REPO_ROOT / "db" / "seed.sql",
        catalog_sql_path=REPO_ROOT / "engine" / "sql" / "catalog.sql",
        demo_pantry=demo_pantry,
    )
    return TestClient(create_app(settings, provider_factory))


@pytest.fixture()
def client():
    return make_client()


@pytest.fixture()
def codes(client):
    """Название → код ингредиента в реальном каталоге."""
    return {ing.name: code for code, ing in client.app.state.catalog.ingredients.items()}


@pytest.fixture()
def receipt_client(codes):
    answer = json.dumps({"items": [
        {"raw_name": raw, "candidates": [{"code": codes[name], "confidence": 0.95}], "quantity": q}
        for raw, name, q in RECEIPT_ITEMS
    ]}, ensure_ascii=False)
    return make_client(provider_factory=lambda: FakeProvider(answer))
