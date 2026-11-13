from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient

from almostdone_server.integrations.yandex import YandexProvider
from almostdone_server.errors import APIError
from ..support.application import create_app
from ..support.http import check


def test_verified_yandex_subject_creates_almostdone_session():
    userinfo = Mock(return_value={
        'client_id': 'our-client', 'id': 'provider-subject', 'default_email': 'ignored@example.org',
    })

    app = create_app(auth_providers={'yandex': YandexProvider('our-client', userinfo)})
    with TestClient(app) as client:
        response = client.post('/api/v1/auth/yandex', json={'oauth_token': 'synthetic-provider-token'})
        session = check(app, response, 'Session')
        userinfo.assert_called_once_with('synthetic-provider-token')
        assert session['access_token'] != 'synthetic-provider-token'
        assert client.get('/api/v1/me', headers={'Authorization': 'Bearer ' + session['access_token']}).status_code == 200


@pytest.mark.parametrize('identity', [{'client_id': 'another-client', 'id': 'subject'},
                                     {'client_id': 'our-client'}, {'client_id': 'our-client', 'id': 123}])
def test_yandex_must_match_client_and_have_subject(identity):
    userinfo = Mock(return_value=identity)
    app = create_app(auth_providers={'yandex': YandexProvider('our-client', userinfo)})
    with TestClient(app) as client:
        check(app, client.post('/api/v1/auth/yandex', json={'oauth_token': 'synthetic-token'}), 'Error', 401)


def test_provider_failure_is_not_reported_as_success():
    userinfo = Mock(side_effect=APIError(503, 'service_unavailable', 'Unavailable'))
    app = create_app(auth_providers={'yandex': YandexProvider('our-client', userinfo)})
    with TestClient(app) as client:
        check(app, client.post('/api/v1/auth/yandex', json={'oauth_token': 'synthetic-token'}), 'Error', 503)


def test_malformed_token_never_reaches_provider():
    userinfo = Mock()
    provider = YandexProvider('our-client', userinfo)
    with pytest.raises(APIError) as error:
        provider.exchange({'oauth_token': 'token\r\nInjected: value'})
    assert error.value.status == 401
    userinfo.assert_not_called()
