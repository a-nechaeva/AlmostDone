from contextlib import contextmanager

import pytest

from almostdone_server.errors import StorageSchemaError, StorageUnavailable
from almostdone_server.repositories.postgres import PostgresStore
from almostdone_server.migrate import migration_files, MIGRATIONS_DIR


def test_unreachable_postgres_is_not_ready():
    pytest.importorskip('psycopg')
    store = PostgresStore('postgresql://test:test@127.0.0.1:1/test?sslmode=disable')
    with pytest.raises(StorageUnavailable):
        store.check_health()


@pytest.mark.parametrize('failure', ['missing_table', 'pending_migration', None])
def test_probe_checks_schema_and_migration_journal(failure, monkeypatch):
    psycopg = pytest.importorskip('psycopg')
    store = PostgresStore('postgresql://not-used/test')
    queries = []
    class Connection:
        def execute(self, query):
            queries.append(query)
            if 'public.auth_sessions' in query and failure == 'missing_table':
                raise psycopg.errors.UndefinedTable('not available')
            return self

        def fetchone(self):
            return (1,)

        def __iter__(self):
            if failure == 'pending_migration':
                return iter([])
            return iter([(path.stem,) for path in migration_files(MIGRATIONS_DIR)])

    @contextmanager
    def connect(dsn, **kwargs):
        assert kwargs['connect_timeout'] == 2
        assert 'statement_timeout=1000' in kwargs['options']
        yield Connection()

    monkeypatch.setattr(store.psycopg, 'connect', connect)
    if failure:
        with pytest.raises((StorageSchemaError, StorageUnavailable)):
            store.check_health()
    else:
        store.check_health()
        assert 'SELECT * FROM public.user_pantry LIMIT 0' in queries
        assert 'SELECT version FROM public.api_schema_migrations' in queries
