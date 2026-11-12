import pytest
from fastapi.testclient import TestClient

from almostdone_server.integrations.yandex import YandexProvider
from almostdone_server.errors import APIError
from ..support.application import create_app
from ..support.http import check


def test_verified_yandex_subject_creates_almostdone_session():
    seen = []

    def userinfo(token):
        seen.append(token)
        return {'client_id': 'our-client', 'id': 'provider-subject', 'default_email': 'ignored@example.org'}

    app = create_app(auth_providers={'yandex': YandexProvider('our-client', userinfo)})
    with TestClient(app) as client:
        response = client.post('/api/v1/auth/yandex', json={'oauth_token': 'synthetic-provider-token'})
        session = check(app, response, 'Session')
        assert seen == ['synthetic-provider-token']
        assert session['access_token'] != seen[0]
        assert client.get('/api/v1/me', headers={'Authorization': 'Bearer ' + session['access_token']}).status_code == 200


@pytest.mark.parametrize('identity', [{'client_id': 'another-client', 'id': 'subject'},
                                     {'client_id': 'our-client'}, {'client_id': 'our-client', 'id': 123}])
def test_yandex_must_match_client_and_have_subject(identity):
    app = create_app(auth_providers={'yandex': YandexProvider('our-client', lambda token: identity)})
    with TestClient(app) as client:
        check(app, client.post('/api/v1/auth/yandex', json={'oauth_token': 'synthetic-token'}), 'Error', 401)


def test_provider_failure_is_not_reported_as_success():
    def unavailable(token):
        raise APIError(503, 'service_unavailable', 'Unavailable')

    app = create_app(auth_providers={'yandex': YandexProvider('our-client', unavailable)})
    with TestClient(app) as client:
        check(app, client.post('/api/v1/auth/yandex', json={'oauth_token': 'synthetic-token'}), 'Error', 503)


def test_malformed_token_never_reaches_provider():
    calls = []
    provider = YandexProvider('our-client', lambda token: calls.append(token))
    with pytest.raises(APIError) as error:
        provider.exchange({'oauth_token': 'token\r\nInjected: value'})
    assert error.value.status == 401 and not calls
