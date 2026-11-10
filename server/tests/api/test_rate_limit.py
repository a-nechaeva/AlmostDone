from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient

from almostdone_server.errors import APIError
from almostdone_server.main import create_app
from almostdone_server.api.rate_limit import RateLimiter
from ..support.http import auth, check


def test_limited_mutation_does_not_modify_state_and_recovers_after_retry():
    now = [0.0]
    limiter = RateLimiter(default_limit=2, clock=lambda: now[0])
    app = create_app(rate_limiter=limiter)
    with TestClient(app) as client:
        headers = auth(app)
        state = client.get("/api/v1/me/state", headers=headers)
        assert client.get("/api/v1/me", headers=headers).status_code == 200
        response = client.put("/api/v1/me/pantry/rice", headers={**headers, "If-Match": state.headers["etag"]},
                              json={"quantity": {"value": 100, "unit": "g"}})
        error = check(app, response, "Error", 429)
        assert error["error"]["code"] == "rate_limited" and error["error"]["retryable"]
        assert response.headers["retry-after"] == "60"
        assert response.headers["cache-control"] == "no-store"
        now[0] = 60
        assert client.get("/api/v1/me/pantry", headers=headers).json()["items"] == []
        assert client.get("/api/v1/me/state", headers=headers).json()["state_version"] == 0


def test_auth_limit_precedes_body_parsing_and_cannot_be_bypassed_with_forwarded_header():
    app = create_app(rate_limiter=RateLimiter(auth_limit=1))
    with TestClient(app) as client:
        assert client.post("/api/v1/auth/yandex", content="not-json").status_code == 422
        response = client.post("/api/v1/auth/yandex", content="not-json", headers={"X-Forwarded-For": "203.0.113.10"})
        check(app, response, "Error", 429)
        assert client.get("/api/v1/health").status_code == 200


def test_limits_are_atomic_and_clients_have_independent_buckets():
    limiter = RateLimiter(default_limit=3)

    def request(_):
        try:
            limiter.check("alice", "/api/v1/me")
            return 200
        except APIError as error:
            return error.status

    with ThreadPoolExecutor(max_workers=8) as pool:
        statuses = list(pool.map(request, range(20)))
    assert statuses.count(200) == 3 and statuses.count(429) == 17
    limiter.check("bob", "/api/v1/me")


def test_expired_buckets_are_reclaimed_and_retry_after_rounds_up():
    now = [10.0]
    limiter = RateLimiter(default_limit=1, max_clients=1, clock=lambda: now[0])
    limiter.check("alice", "/api/v1/me")
    now[0] = 69.5
    with pytest.raises(APIError) as error:
        limiter.check("alice", "/api/v1/me")
    assert error.value.headers["Retry-After"] == "1"
    now[0] = 70
    limiter.check("bob", "/api/v1/me")
    assert len(limiter._buckets) == 1
