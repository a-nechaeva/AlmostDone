import asyncio

from fastapi import FastAPI
from fastapi.responses import StreamingResponse
from fastapi.testclient import TestClient
from almostdone_server.api.metrics import install_metrics


def sample(app, name, **labels):
    return app.state.http_metrics.registry.get_sample_value(name, labels)


def test_real_api_metrics_exclude_probes_and_scrapes(client, app):
    for path in ("/api/v1/health", "/api/v1/health/ready", "/docs", "/metrics"):
        client.get(path)
    assert list(app.state.http_metrics.requests.collect())[0].samples == []
    assert client.get("/api/v1/me").status_code == 401
    assert sample(app, "almostdone_http_requests_total",
                  method="GET", route="/api/v1/me", status="401") == 1
    response = client.get("/metrics")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain")
    assert "almostdone_http_requests_total" in response.text


def test_route_templates_and_unmatched_paths_bound_cardinality():
    app = FastAPI()

    @app.get("/api/v1/items/{item_id}")
    def item(item_id: str):
        return {"id": item_id}

    install_metrics(app)
    with TestClient(app) as client:
        client.get("/api/v1/items/private-id?token=private-token")
        client.get("/api/v1/items/another-id")
        client.get("/api/v1/missing-one")
        client.get("/api/v1/missing-two")
        body = client.get("/metrics").text
    assert sample(app, "almostdone_http_requests_total",
                  method="GET", route="/api/v1/items/{item_id}", status="200") == 2
    assert sample(app, "almostdone_http_requests_total",
                  method="GET", route="unmatched", status="404") == 2
    assert "private-id" not in body and "private-token" not in body
    assert "missing-one" not in body and "another-id" not in body


def test_unhandled_exceptions_are_counted_and_gauge_is_released():
    app = FastAPI()

    @app.get("/api/v1/fail")
    def fail():
        raise RuntimeError("synthetic failure")

    install_metrics(app)
    with TestClient(app, raise_server_exceptions=False) as client:
        assert client.get("/api/v1/fail").status_code == 500
    assert sample(app, "almostdone_http_requests_total",
                  method="GET", route="/api/v1/fail", status="500") == 1
    assert sample(app, "almostdone_http_requests_in_progress") == 0
    assert sample(app, "almostdone_http_request_duration_seconds_count",
                  method="GET", route="/api/v1/fail") == 1


def test_streaming_request_is_in_progress_until_last_chunk():
    app = FastAPI()

    async def stream():
        assert sample(app, "almostdone_http_requests_in_progress") == 1
        yield b"first"
        await asyncio.sleep(0)
        assert sample(app, "almostdone_http_requests_in_progress") == 1
        yield b"last"

    @app.get("/api/v1/stream")
    def endpoint():
        return StreamingResponse(stream())

    install_metrics(app)
    with TestClient(app) as client:
        assert client.get("/api/v1/stream").content == b"firstlast"
    assert sample(app, "almostdone_http_requests_in_progress") == 0


def test_registries_are_isolated():
    first, second = FastAPI(), FastAPI()
    install_metrics(first)
    install_metrics(second)
    with TestClient(first) as client:
        client.get("/api/v1/missing")
    assert sample(first, "almostdone_http_requests_total",
                  method="GET", route="unmatched", status="404") == 1
    assert sample(second, "almostdone_http_requests_total",
                  method="GET", route="unmatched", status="404") is None
