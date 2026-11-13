import io
import json
from urllib.error import HTTPError, URLError
from unittest.mock import Mock, patch

import pytest

from almostdone_server.integrations import yandex as auth
from almostdone_server.errors import APIError


@pytest.fixture
def transport():
    opener = Mock(spec=["open"])
    with patch.object(auth, "build_opener", autospec=True, return_value=opener) as build_opener:
        yield opener, build_opener


def test_token_uses_authorization_header_and_fixed_url(transport):
    opener, build_opener = transport
    opener.open.return_value = io.BytesIO(json.dumps({"client_id": "client", "id": "subject"}).encode())
    assert auth.YandexProvider("client").exchange({"oauth_token": "synthetic-token"}) == "subject"
    opener.open.assert_called_once()
    request = opener.open.call_args.args[0]
    assert request.full_url == "https://login.yandex.ru/info?format=json"
    assert request.get_header("Authorization") == "OAuth synthetic-token"
    assert opener.open.call_args.kwargs == {"timeout": 10}
    build_opener.assert_called_once()
    handlers = build_opener.call_args.args
    redirect = next(h for h in handlers if hasattr(h, "redirect_request"))
    assert redirect.redirect_request(None, None, 302, "Redirect", {}, "https://example.org") is None
    assert any(isinstance(h, auth.HTTPSHandler) for h in handlers)


@pytest.mark.parametrize("status, expected", [(400, 401), (401, 401), (403, 401),
                                             (302, 503), (429, 503), (500, 503)])
def test_provider_http_errors_are_mapped_without_echoing_tokens(transport, status, expected):
    error = HTTPError("https://login.yandex.ru/info", status, "synthetic-token", {}, io.BytesIO(b"private-response"))
    transport[0].open.side_effect = error
    with pytest.raises(APIError) as raised:
        auth.YandexProvider("client").exchange({"oauth_token": "synthetic-token"})
    assert raised.value.status == expected
    assert "synthetic-token" not in json.dumps(raised.value.body())
    assert error.fp.closed


@pytest.mark.parametrize("body", [b"not-json", b"x" * 65537])
def test_invalid_provider_response_is_unavailable(transport, body):
    transport[0].open.return_value = io.BytesIO(body)
    with pytest.raises(APIError) as raised:
        auth.YandexProvider("client").exchange({"oauth_token": "synthetic-token"})
    assert raised.value.status == 503


def test_network_failure_is_unavailable(transport):
    transport[0].open.side_effect = URLError("private network details")
    with pytest.raises(APIError) as raised:
        auth.YandexProvider("client").exchange({"oauth_token": "synthetic-token"})
    assert raised.value.status == 503
