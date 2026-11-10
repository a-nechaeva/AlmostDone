"""Shared HTTP fixtures for all server test packages."""
import pytest
from fastapi.testclient import TestClient
from almostdone_server.main import create_app


@pytest.fixture
def app(tmp_path):
    return create_app()


@pytest.fixture
def client(app):
    with TestClient(app) as client:
        yield client
