"""Application use cases exercised directly, without FastAPI or HTTP requests."""
import copy
from dataclasses import replace
from uuid import uuid4

import pytest

from ..support.catalog import custom_catalog, make_catalog
from almostdone_server.errors import APIError
from ..support.memory import Store
from almostdone_server.services.application import ApplicationService
from almostdone_server.services.commands import Command


@pytest.fixture
def application():
    data = custom_catalog()
    store, catalog = Store(), make_catalog(data)
    service = ApplicationService(store, catalog, {}, None, None)
    with store.transaction() as db:
        token = service.auth.issue(db, "alice")["access_token"]
    return service, token


def add_command(token):
    return Command("pantry_add", {"ingredient_id": "rice", "quantity": {"value": 100, "unit": "g"}},
                   access_token=token, expected_version=0, idempotency_key=str(uuid4()))


def test_retry_returns_original_result_before_checking_stale_version(application):
    service, token = application
    command = add_command(token)
    first = service.execute(command)
    assert first.version == 1
    assert service.execute(command) == first
    state = service.execute(Command("pantry_get", access_token=token))
    assert state.data["items"][0]["quantity"]["value"] == 100


def test_direct_service_call_cannot_skip_state_precondition(application):
    service, token = application
    with pytest.raises(APIError) as error:
        service.execute(replace(add_command(token), expected_version=None))
    assert error.value.code == "precondition_required"
    assert service.execute(Command("pantry_get", access_token=token)).data["items"] == []


def test_batch_validation_rolls_back_every_item_and_retry_record(application):
    service, token = application
    command = Command("pantry_add_purchased", {"items": [
        {"ingredient_id": "rice", "quantity": {"value": 100, "unit": "g"}},
        {"ingredient_id": "missing", "quantity": {"value": 100, "unit": "g"}},
    ]}, access_token=token, expected_version=0, idempotency_key=str(uuid4()))
    before = copy.deepcopy(service.store.runtime._data)
    with pytest.raises(APIError):
        service.execute(command)
    assert service.store.runtime._data == before


def test_result_validation_failure_rolls_back_mutation_and_retry_record(application):
    service, token = application
    before = copy.deepcopy(service.store.runtime._data)

    def reject_result(result):
        assert result.data["state_version"] == 1
        raise APIError(500, "internal_error", "Invalid result")

    with pytest.raises(APIError):
        service.execute(add_command(token), reject_result)
    assert service.store.runtime._data == before


def test_recipe_service_delegates_calculation_to_existing_engine(application, monkeypatch):
    service, token = application
    engine = service.catalog.gateway.engine
    if engine is None:
        pytest.skip("dishgraph is not installed")
    original, calls = engine.dish_option, []

    def calculate(*args, **kwargs):
        calls.append(args)
        return original(*args, **kwargs)

    monkeypatch.setattr(engine, "dish_option", calculate)
    recipe_id = next(iter(service.catalog.recipes))
    result = service.execute(Command("recipes_get", parameters={"recipe_id": recipe_id, "servings": 2}, access_token=token))
    assert result.data["recipe"]["id"] == recipe_id
    assert len(calls) == 1


def test_server_factory_requires_an_explicit_database(monkeypatch):
    from almostdone_server.main import create_app as create_server_app
    monkeypatch.delenv("ALMOSTDONE_DATABASE_URL", raising=False)
    with pytest.raises(RuntimeError, match="ALMOSTDONE_DATABASE_URL is required"):
        create_server_app()
