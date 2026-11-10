from contextlib import contextmanager

import pytest

from fastapi.testclient import TestClient

from almostdone_server.errors import APIError, StorageUnavailable
from almostdone_server.main import create_app
from almostdone_server.repositories.memory import Store


@pytest.mark.parametrize("failure", [APIError(503, "service_unavailable", "Unavailable"), StorageUnavailable("Unavailable")])
def test_temporary_cleanup_outage_does_not_break_server_shutdown(failure):
    class UnavailableDuringCleanup(Store):
        @contextmanager
        def transaction(self):
            raise failure
            yield
    with TestClient(create_app(store=UnavailableDuringCleanup())) as client:
        assert client.get("/api/v1/health").status_code == 200
