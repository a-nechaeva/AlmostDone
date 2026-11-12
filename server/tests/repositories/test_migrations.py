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


def test_first_migration_bootstraps_journal_and_preserves_existing_users(database, tmp_path):
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
            # This test deliberately has only the users table; catalogue
            # changes are covered separately against a complete base schema.
            (tmp_path / '001_server_state.sql').write_bytes((MIGRATIONS_DIR / '001_server_state.sql').read_bytes())
            first = run_migrations(dsn, tmp_path)
            second = run_migrations(dsn, tmp_path)
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


@pytest.fixture
def catalogue_database(database):
    from almostdone_server.repositories.catalog import SeedDump
    from ..support.paths import PROJECT_ROOT
    name = "almostdone_catalogue_" + uuid4().hex + "_test"
    with psycopg.connect(database, autocommit=True) as admin:
        try:
            admin.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(name)))
        except psycopg.errors.InsufficientPrivilege:
            pytest.skip("Catalogue migration test requires CREATEDB")
        try:
            dsn = make_conninfo(database, dbname=name)
            with psycopg.connect(dsn) as connection:
                connection.execute((PROJECT_ROOT / "db/schema.sql").read_text(encoding="utf-8"), prepare=False)
                connection.execute("SET search_path TO public, pg_catalog")
                for table, rows in SeedDump(PROJECT_ROOT / "db/seed.sql").tables.items():
                    if not rows:
                        continue
                    columns = list(rows[0])
                    statement = sql.SQL("COPY public.{} ({}) FROM STDIN").format(
                        sql.Identifier(table), sql.SQL(", ").join(map(sql.Identifier, columns)))
                    with connection.cursor().copy(statement) as stream:
                        for row in rows:
                            stream.write_row([row[column] for column in columns])
            yield dsn
        finally:
            admin.execute(sql.SQL("DROP DATABASE {} WITH (FORCE)").format(sql.Identifier(name)))


def test_volume_migration_preserves_catalogue_and_user_state(catalogue_database, tmp_path):
    # Exercise the volume migration independently of later catalogue changes.
    (tmp_path / "002_ingredient_volume.sql").write_bytes((MIGRATIONS_DIR / "002_ingredient_volume.sql").read_bytes())
    dsn = catalogue_database
    with psycopg.connect(dsn) as connection:
        connection.execute("UPDATE ingredients SET kcal=0,protein=0,fat=0,carbs=0 WHERE id=12")
        connection.execute("DELETE FROM recipe_ingredients WHERE recipe_id=1")
        connection.execute("INSERT INTO users(id,login,password_hash) VALUES (100000,'migration-user','hash')")
        connection.execute("INSERT INTO user_pantry(user_id,ingredient_id,qty_g) VALUES (100000,12,123)")
        connection.execute("INSERT INTO favorite_recipes(user_id,recipe_id) VALUES (100000,1)")
        connection.execute("INSERT INTO favorite_ingredients(user_id,ingredient_id) VALUES (100000,12)")
        connection.execute("INSERT INTO user_api_state(user_id,state_version,diabetes) VALUES (100000,7,true)")
        connection.execute("INSERT INTO user_identities(user_id,provider,provider_subject) VALUES (100000,'yandex','existing-subject')")
        connection.execute("INSERT INTO auth_sessions(id,user_id,expires_at) VALUES (%s,100000,now()+interval '1 day')", (uuid4(),))
        connection.execute("INSERT INTO recipes(id,title,servings,cook_time_min,author_id) VALUES (100000,'Personal recipe',2,10,100000)")
        connection.execute("INSERT INTO recipe_ingredients(recipe_id,ingredient_id,qty_g) VALUES (100000,12,50)")
        # Products removed from the bundled seed must retain existing references.
        connection.execute("INSERT INTO ingredients SELECT 100000,'retired_product','Retired product',is_staple,display_unit,grams_per_piece,kcal,protein,fat,carbs,package_g,package_price FROM ingredients WHERE id=12")
        connection.execute("INSERT INTO user_pantry(user_id,ingredient_id,qty_g) VALUES (100000,100000,50)")
        protected = ["users", "user_pantry", "favorite_recipes", "favorite_ingredients", "user_api_state",
                     "user_identities", "auth_sessions", "user_diets", "user_allergens"]
        def snapshot():
            return {table: sorted(row[0] for row in connection.execute(sql.SQL(
                "SELECT row_to_json(t)::text FROM public.{} t").format(sql.Identifier(table)))) for table in protected}
        before = snapshot()
    first = run_migrations(dsn, tmp_path)
    assert first.applied == ("002_ingredient_volume",)
    with psycopg.connect(dsn) as connection:
        assert snapshot() == before
        assert connection.execute("SELECT kcal,protein,fat,carbs FROM ingredients WHERE id=12").fetchone() == (0, 0, 0, 0)
        assert connection.execute("SELECT count(*) FROM recipe_ingredients WHERE recipe_id=1").fetchone()[0] == 0
        assert connection.execute("SELECT title,author_id FROM recipes WHERE id=100000").fetchone() == ("Personal recipe",100000)
        assert connection.execute("SELECT qty_g FROM recipe_ingredients WHERE recipe_id=100000").fetchone()[0] == 50
        assert connection.execute("SELECT grams_per_ml FROM ingredients WHERE id=12").fetchone()[0] is not None
        densities = dict(connection.execute("SELECT id,grams_per_ml FROM ingredients WHERE id IN (25,43,59,100000)"))
        assert float(densities[25]) == 1.11
        assert float(densities[43]) == 1.05
        assert float(densities[59]) == 1.43
        assert densities[100000] is None
        # A repeated deployment must not reset new edits or reload the snapshot.
        connection.execute("UPDATE ingredients SET kcal=1 WHERE id=12")
    assert run_migrations(dsn, tmp_path).applied == ()
    with psycopg.connect(dsn) as connection:
        assert connection.execute("SELECT kcal FROM ingredients WHERE id=12").fetchone()[0] == 1
        assert snapshot() == before
