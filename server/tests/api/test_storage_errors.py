"""Persistence failures are presented as HTTP errors only by the API layer."""
import pytest
from fastapi.testclient import TestClient

from almostdone_server.errors import (APIError, StorageUnavailable, StorageSchemaError,
                                      StorageConflict, StorageValueError)
from ..support.application import create_app
from ..support.http import auth, check, session


@pytest.mark.parametrize("failure,status", [
    (StorageUnavailable("Unavailable"), 503),
    (StorageSchemaError("Schema mismatch"), 503),
    (StorageConflict("Related data changed"), 409),
    (StorageValueError("Quantity does not fit column", "quantity"), 422),
])
def test_storage_exception_is_mapped_at_http_boundary(monkeypatch, failure, status):
    app = create_app()
    headers = auth(app)

    def fail(*args):
        raise failure

    monkeypatch.setattr(app.state.service.store, "user", fail)
    with TestClient(app) as client:
        body = check(app, client.get("/api/v1/me", headers=headers), "Error", status)
        assert body["error"]["retryable"] is (status == 503)


def test_refresh_response_validation_failure_does_not_revoke_client_session(monkeypatch):
    app = create_app()
    original = session(app)
    headers = {"Authorization": "Bearer " + original["access_token"]}
    validate = app.state.contract.response

    def reject_refresh(operation_id, status, data):
        if operation_id == "auth_refresh":
            raise APIError(500, "internal_error", "Rejected response")
        return validate(operation_id, status, data)

    monkeypatch.setattr(app.state.contract, "response", reject_refresh)
    with TestClient(app) as client:
        body = {"refresh_token": original["refresh_token"]}
        check(app, client.post("/api/v1/auth/refresh", json=body), "Error", 500)
        assert client.get("/api/v1/me", headers=headers).status_code == 200
        monkeypatch.setattr(app.state.contract, "response", validate)
        assert client.post("/api/v1/auth/refresh", json=body).status_code == 200
        assert client.get("/api/v1/me", headers=headers).status_code == 401
