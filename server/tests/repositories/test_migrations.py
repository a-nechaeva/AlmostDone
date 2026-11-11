"""The local command and Docker migrator use the same real PostgreSQL journal."""
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from uuid import uuid4

import pytest

psycopg = pytest.importorskip("psycopg")
from psycopg import sql
from psycopg.conninfo import make_conninfo

from almostdone_server.migrate import MIGRATIONS_DIR, main, run_migrations
from .test_postgres import database, pytestmark


@pytest.fixture
def migration_case(database, tmp_path):
    suffix = uuid4().hex
    version = '900001_probe_' + suffix
    table = 'migration_probe_' + suffix
    path = tmp_path / (version + '.sql')
    try:
        yield tmp_path, path, version, table
    finally:
        with psycopg.connect(database) as connection:
            connection.execute(sql.SQL('DROP TABLE IF EXISTS {}').format(sql.Identifier(table)))
            connection.execute('DELETE FROM public.api_schema_migrations WHERE version=%s', (version,))


def test_already_applied_migration_is_not_executed(database, tmp_path):
    # This version is part of the seeded test database; invalid SQL proves skip
    # is based on the journal, not on idempotent CREATE statements.
    (tmp_path / '001_server_state.sql').write_text('THIS MUST NEVER BE EXECUTED;', encoding='utf-8')
    report = run_migrations(database, tmp_path)
    assert report.applied == ()
    assert report.skipped == ('001_server_state',)


def test_pending_migration_is_applied_only_once(database, migration_case):
    directory, path, version, table = migration_case
    path.write_text(f'CREATE TABLE public.{table}(value INTEGER); INSERT INTO public.{table} VALUES (7);', encoding='utf-8')
    first = run_migrations(database, directory)
    second = run_migrations(database, directory)
    assert first.applied == (version,) and first.skipped == ()
    assert second.applied == () and second.skipped == (version,)
    with psycopg.connect(database) as connection:
        assert connection.execute(sql.SQL('SELECT value FROM {}').format(sql.Identifier(table))).fetchall() == [(7,)]


def test_failed_migration_rolls_back_and_command_can_retry(database, migration_case, capsys):
    directory, path, version, table = migration_case
    path.write_text(f'CREATE TABLE public.{table}(value INTEGER); SELECT unknown_migration_column;', encoding='utf-8')
    args = ['--database-url', database, '--migrations-dir', str(directory)]
    assert main(args) == 1
    output = capsys.readouterr()
    assert 'Migration failed:' in output.err
    assert database not in output.err
    with psycopg.connect(database) as connection:
        assert connection.execute('SELECT to_regclass(%s)', ('public.' + table,)).fetchone()[0] is None
        assert connection.execute('SELECT 1 FROM public.api_schema_migrations WHERE version=%s', (version,)).fetchone() is None
    path.write_text(f'CREATE TABLE public.{table}(value INTEGER);', encoding='utf-8')
    assert main(args) == 0


def test_concurrent_migrators_execute_the_file_once(database, migration_case):
    directory, path, version, table = migration_case
    path.write_text(f'CREATE TABLE public.{table}(value INTEGER); SELECT pg_sleep(0.2); INSERT INTO public.{table} VALUES (1);', encoding='utf-8')
    barrier = Barrier(2)

    def migrate(_):
        barrier.wait()
        return run_migrations(database, directory)

    with ThreadPoolExecutor(max_workers=2) as pool:
        reports = list(pool.map(migrate, range(2)))
    assert sorted(len(report.applied) for report in reports) == [0, 1]
    assert sorted(len(report.skipped) for report in reports) == [0, 1]
    with psycopg.connect(database) as connection:
        assert connection.execute(sql.SQL('SELECT count(*) FROM {}').format(sql.Identifier(table))).fetchone()[0] == 1


def test_migrations_follow_numeric_order(database, tmp_path):
    suffix = uuid4().hex
    table = 'migration_order_' + suffix
    versions = ('2_create_' + suffix, '10_insert_' + suffix)
    (tmp_path / (versions[0] + '.sql')).write_text(f'CREATE TABLE public.{table}(value INTEGER);', encoding='utf-8')
    (tmp_path / (versions[1] + '.sql')).write_text(f'INSERT INTO public.{table} VALUES (10);', encoding='utf-8')
    try:
        assert run_migrations(database, tmp_path).applied == versions
        with psycopg.connect(database) as connection:
            assert connection.execute(sql.SQL('SELECT value FROM {}').format(sql.Identifier(table))).fetchone()[0] == 10
    finally:
        with psycopg.connect(database) as connection:
            connection.execute(sql.SQL('DROP TABLE IF EXISTS {}').format(sql.Identifier(table)))
            connection.execute('DELETE FROM public.api_schema_migrations WHERE version=ANY(%s)', (list(versions),))


def test_first_migration_bootstraps_journal_and_preserves_existing_users(database):
    # A separate database is needed to test the absence of the journal without
    # renaming or deleting metadata used by the other application tests.
    name = 'almostdone_migration_' + uuid4().hex + '_test'
    with psycopg.connect(database, autocommit=True) as admin:
        try:
            admin.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(name)))
        except psycopg.errors.InsufficientPrivilege:
            pytest.skip('Journal bootstrap test requires CREATEDB on the test role')
        try:
            dsn = make_conninfo(database, dbname=name)
            with psycopg.connect(dsn) as connection:
                connection.execute('CREATE TABLE public.users(id SERIAL PRIMARY KEY, login TEXT NOT NULL)')
                connection.execute("INSERT INTO public.users(login) VALUES ('existing-user')")
            first = run_migrations(dsn, MIGRATIONS_DIR)
            second = run_migrations(dsn, MIGRATIONS_DIR)
            assert first.applied == ('001_server_state',)
            assert second.skipped == ('001_server_state',)
            with psycopg.connect(dsn) as connection:
                assert connection.execute('SELECT login FROM public.users').fetchall() == [('existing-user',)]
                assert connection.execute('SELECT state_version FROM public.user_api_state').fetchall() == [(0,)]
                assert connection.execute('SELECT version FROM public.api_schema_migrations').fetchall() == [('001_server_state',)]
        finally:
            admin.execute(sql.SQL('DROP DATABASE {}').format(sql.Identifier(name)))


def test_cli_requires_an_explicit_database(monkeypatch):
    monkeypatch.delenv('ALMOSTDONE_DATABASE_URL', raising=False)
    with pytest.raises(SystemExit) as error:
        main([])
    assert error.value.code == 2
