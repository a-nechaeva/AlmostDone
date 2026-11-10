import io
import json
from urllib.error import HTTPError, URLError

import pytest

from almostdone_server.integrations import yandex as auth
from almostdone_server.errors import APIError


def install_transport(monkeypatch, *, body=None, error=None):
    calls = []

    class Opener:
        def open(self, request, timeout):
            calls.append((request, timeout))
            if error:
                raise error
            return io.BytesIO(body)

    def build_opener(handler):
        assert handler.redirect_request(None, None, 302, "Redirect", {}, "https://example.org") is None
        return Opener()

    monkeypatch.setattr(auth, "build_opener", build_opener)
    return calls


def test_token_uses_authorization_header_and_fixed_url(monkeypatch):
    calls = install_transport(monkeypatch, body=json.dumps({"client_id": "client", "id": "subject"}).encode())
    assert auth.YandexProvider("client").exchange({"oauth_token": "synthetic-token"}) == "subject"
    request, timeout = calls[0]
    assert request.full_url == "https://login.yandex.ru/info?format=json"
    assert request.get_header("Authorization") == "OAuth synthetic-token"
    assert timeout == 10


@pytest.mark.parametrize("status, expected", [(400, 401), (401, 401), (403, 401),
                                             (302, 503), (429, 503), (500, 503)])
def test_provider_http_errors_are_mapped_without_echoing_tokens(monkeypatch, status, expected):
    error = HTTPError("https://login.yandex.ru/info", status, "synthetic-token", {}, io.BytesIO(b"private-response"))
    install_transport(monkeypatch, error=error)
    with pytest.raises(APIError) as raised:
        auth.YandexProvider("client").exchange({"oauth_token": "synthetic-token"})
    assert raised.value.status == expected
    assert "synthetic-token" not in json.dumps(raised.value.body())
    assert error.fp.closed


@pytest.mark.parametrize("body", [b"not-json", b"x" * 65537])
def test_invalid_provider_response_is_unavailable(monkeypatch, body):
    install_transport(monkeypatch, body=body)
    with pytest.raises(APIError) as raised:
        auth.YandexProvider("client").exchange({"oauth_token": "synthetic-token"})
    assert raised.value.status == 503


def test_network_failure_is_unavailable(monkeypatch):
    install_transport(monkeypatch, error=URLError("private network details"))
    with pytest.raises(APIError) as raised:
        auth.YandexProvider("client").exchange({"oauth_token": "synthetic-token"})
    assert raised.value.status == 503
