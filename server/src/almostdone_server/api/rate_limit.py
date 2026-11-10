"""Per-client request limits for the single-process server."""
import math
import threading
import time

from ..errors import APIError


class RateLimiter:
    def __init__(self, *, default_limit=120, auth_limit=10, recognition_limit=10,
                 recommendation_limit=30, window=60, max_clients=10000, clock=time.monotonic):
        values = (default_limit, auth_limit, recognition_limit, recommendation_limit, max_clients)
        if any(isinstance(value, bool) or not isinstance(value, int) or value <= 0 for value in values):
            raise ValueError("Request limits must be positive integers")
        if not math.isfinite(window) or window <= 0:
            raise ValueError("Rate limit window must be positive")
        self.limits = {"default": default_limit, "auth": auth_limit,
                       "recognition": recognition_limit, "recommendation": recommendation_limit}
        self.window, self.max_clients, self.clock = window, max_clients, clock
        self._buckets = {}
        self._lock = threading.Lock()
        self._cleanup_after = 0

    def check(self, client, path):
        if path.startswith("/api/v1/auth/"):
            group = "auth"
        elif path == "/api/v1/recognitions":
            group = "recognition"
        elif path == "/api/v1/recommendations":
            group = "recommendation"
        else:
            group = "default"
        key = (client, group)
        with self._lock:
            now = self.clock()
            if now >= self._cleanup_after or len(self._buckets) >= self.max_clients:
                self._buckets = {key: value for key, value in self._buckets.items() if value[1] > now}
                self._cleanup_after = now + min(self.window, 1)
            count, until = self._buckets.get(key, (0, now + self.window))
            if until <= now:
                count, until = 0, now + self.window
            if count >= self.limits[group] or key not in self._buckets and len(self._buckets) >= self.max_clients:
                retry = max(1, math.ceil(until - now))
                raise APIError(429, "rate_limited", "Слишком много запросов; повторите позже",
                               headers={"Retry-After": str(retry)})
            self._buckets[key] = (count + 1, until)
