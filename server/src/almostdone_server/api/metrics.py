"""Bounded HTTP metrics, with a registry owned by each application instance."""
from time import perf_counter

from fastapi.responses import Response
from prometheus_client import (
    CollectorRegistry, Counter, Gauge, Histogram, ProcessCollector,
    CONTENT_TYPE_LATEST, generate_latest,
)


EXCLUDED_PATHS = {"/api/v1/health", "/api/v1/health/ready"}
METHODS = {"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"}


class HttpMetrics:
    def __init__(self):
        self.registry = CollectorRegistry()
        ProcessCollector(registry=self.registry)
        self.requests = Counter(
            "almostdone_http_requests_total", "Completed API requests",
            ["method", "route", "status"], registry=self.registry,
        )
        self.duration = Histogram(
            "almostdone_http_request_duration_seconds", "Full API response duration",
            ["method", "route"], registry=self.registry,
            buckets=(.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10, 30, 60),
        )
        self.in_progress = Gauge(
            "almostdone_http_requests_in_progress", "API requests currently being processed",
            registry=self.registry,
        )


class HttpMetricsMiddleware:
    def __init__(self, app, metrics):
        self.app = app
        self.metrics = metrics

    async def __call__(self, scope, receive, send):
        path = scope.get("path", "")
        if (scope["type"] != "http" or not path.startswith("/api/v1/")
                or path in EXCLUDED_PATHS):
            await self.app(scope, receive, send)
            return

        method = scope["method"] if scope["method"] in METHODS else "OTHER"
        status = 500
        started = perf_counter()
        self.metrics.in_progress.inc()

        async def observe_send(message):
            nonlocal status
            if message["type"] == "http.response.start":
                status = message["status"]
            await send(message)

        try:
            await self.app(scope, receive, observe_send)
        finally:
            # Templates aggregate IDs. Never label by raw URL, query, token or user.
            route = getattr(scope.get("route"), "path", "unmatched")
            self.metrics.in_progress.dec()
            self.metrics.requests.labels(method, route, str(status)).inc()
            self.metrics.duration.labels(method, route).observe(perf_counter() - started)


def install_metrics(app):
    metrics = HttpMetrics()
    app.state.http_metrics = metrics

    @app.get("/metrics", include_in_schema=False)
    def metrics_endpoint():
        return Response(generate_latest(metrics.registry),
                        headers={"Content-Type": CONTENT_TYPE_LATEST,
                                 "Cache-Control": "no-store"})

    app.add_middleware(HttpMetricsMiddleware, metrics=metrics)
