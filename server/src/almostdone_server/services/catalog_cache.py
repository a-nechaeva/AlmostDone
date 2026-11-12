"""Atomically publish validated PostgreSQL catalogue snapshots without restarting."""
from contextlib import contextmanager
from contextvars import ContextVar
from threading import Lock

from .catalog import Catalog
from ..repositories.catalog import MemoryCatalogRepository


class CatalogCache:
    def __init__(self, repository, gateway_factory, validate):
        self._repository = repository
        self._gateway_factory = gateway_factory
        self._validate = validate
        self._refresh_lock = Lock()
        self._pinned = ContextVar('catalogue_snapshot', default=None)
        data, self._revision = repository.load_versioned()
        self._current = Catalog(MemoryCatalogRepository(data), gateway_factory())

    def __getattr__(self, name):
        return getattr(self._pinned.get() or self._current, name)

    @contextmanager
    def pin(self):
        """Every access in an operation sees one catalogue, including its engine."""
        token = self._pinned.set(self._pinned.get() or self._current)
        try:
            yield
        finally:
            self._pinned.reset(token)

    def listen(self):
        return self._repository.listen()

    def refresh(self):
        if not self._refresh_lock.acquire(blocking=False):
            return False
        try:
            if self._repository.revision() == self._revision:
                return False
            data, revision = self._repository.load_versioned()
            candidate = Catalog(MemoryCatalogRepository(data), self._gateway_factory())
            # Build the export and validate the contract before publishing anything.
            # A failed build/validation leaves the previous snapshot and marker intact.
            self._validate(candidate)
            self._current = candidate
            self._revision = revision
            return True
        finally:
            self._refresh_lock.release()
