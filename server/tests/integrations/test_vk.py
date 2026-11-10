
import pytest
from fastapi.testclient import TestClient

from almostdone_server.errors import APIError
from almostdone_server.main import create_app
from almostdone_server.integrations.vk import VkProvider
from ..support.http import check

PAYLOAD = {"authorization_code": "synthetic-code", "device_id": "synthetic-device",
           "code_verifier": "x" * 43, "redirect_uri": "https://example.org/callback"}


def test_vk_checks_pkce_redirect_and_verified_subject_before_issuing_session():
    calls = []

    def request(url, fields):
        calls.append((url, fields))
        if url == VkProvider.TOKEN_URL:
            assert fields["client_id"] == "our-client"
            assert fields["code_verifier"] == PAYLOAD["code_verifier"]
            assert fields["device_id"] == PAYLOAD["device_id"]
            return {"access_token": "provider-token", "user_id": 42, "state": fields["state"]}
        assert fields == {"client_id": "our-client", "access_token": "provider-token"}
        return {"user": {"user_id": "42", "email": "ignored@example.org"}}

    provider = VkProvider("our-client", PAYLOAD["redirect_uri"], request=request)
    app = create_app(auth_providers={"vk": provider})
    with TestClient(app) as client:
        session = check(app, client.post("/api/v1/auth/vk", json=PAYLOAD), "Session")
        assert len(calls) == 2
        assert session["access_token"] != "provider-token"
        assert client.get("/api/v1/me", headers={"Authorization": "Bearer " + session["access_token"]}).status_code == 200


def test_vk_rejects_unconfigured_redirect_before_contacting_provider():
    calls = []
    provider = VkProvider("client", "https://example.org/other", request=lambda *args: calls.append(args))
    with pytest.raises(APIError) as error:
        provider.exchange(PAYLOAD)
    assert error.value.status == 401 and not calls


@pytest.mark.parametrize("failure", ["state", "subject", "missing_access"])
def test_vk_rejects_inconsistent_provider_identity(failure):
    def request(url, fields):
        if url == VkProvider.TOKEN_URL:
            return {"state": "wrong" if failure == "state" else fields["state"], "user_id": "42",
                    "access_token": "" if failure == "missing_access" else "synthetic-token"}
        return {"user": {"user_id": "different" if failure == "subject" else "42"}}
    app = create_app(auth_providers={"vk": VkProvider("client", PAYLOAD["redirect_uri"], request=request)})
    with TestClient(app) as client:
        check(app, client.post("/api/v1/auth/vk", json=PAYLOAD), "Error", 401)
        assert not app.state.service.store.runtime._data.get("sessions", {})


def test_vk_environment_configuration(monkeypatch):
    monkeypatch.setenv("ALMOSTDONE_VK_CLIENT_ID", "client")
    monkeypatch.setenv("ALMOSTDONE_VK_REDIRECT_URI", PAYLOAD["redirect_uri"])
    assert isinstance(create_app().state.service.auth_providers["vk"], VkProvider)
