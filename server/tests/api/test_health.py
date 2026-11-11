from fastapi.testclient import TestClient
import pytest

from almostdone_server.errors import StorageUnavailable
from almostdone_server.main import create_app
from almostdone_server.api.rate_limit import RateLimiter


def test_readiness_is_public_and_validates_against_contract():
    app = create_app(auth_providers={})
    with TestClient(app) as client:
        response = client.get('/api/v1/health/ready')
    assert response.status_code == 200
    assert response.headers['cache-control'] == 'no-store'
    assert response.json()['checks'] == {
        'storage': 'ok', 'engine': 'ok', 'catalog': 'ok',
        'yandex': 'disabled', 'recognition': 'disabled',
    }
    app.state.contract.response('readiness_get', 200, response.json())


@pytest.mark.parametrize('component', ['storage', 'engine', 'catalog'])
def test_dependency_failure_changes_readiness_but_not_liveness(component, monkeypatch):
    app = create_app()
    service = app.state.service
    def unavailable():
        raise StorageUnavailable('secret database credentials must not be exposed')
    if component == 'storage':
        monkeypatch.setattr(service.store, 'check_health', unavailable)
    elif component == 'engine':
        monkeypatch.setattr(service.catalog, 'require_engine', unavailable)
    else:
        service.catalog.ingredients = {}
    with TestClient(app) as client:
        response = client.get('/api/v1/health/ready')
        assert client.get('/api/v1/health').status_code == 200
    assert response.status_code == 503
    assert response.json()['error']['details'][0]['field'] == component
    assert 'secret' not in response.text
    app.state.contract.response('readiness_get', 503, response.json())


def test_probes_are_not_blocked_by_api_rate_limit():
    app = create_app(rate_limiter=RateLimiter(default_limit=1))
    with TestClient(app) as client:
        client.get('/api/v1/me')
        assert client.get('/api/v1/me').status_code == 429
        for _ in range(3):
            assert client.get('/api/v1/health').status_code == 200
            assert client.get('/api/v1/health/ready').status_code == 200
