"""Apply pending SQL migrations atomically, with one migrator per database."""
import argparse
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path


MIGRATIONS_DIR = Path(__file__).resolve().parents[3] / "db" / "migrations"
MIGRATION_LOCK = int.from_bytes(b"AlmostDn", "big")


class MigrationError(Exception):
    pass


@dataclass(frozen=True)
class MigrationReport:
    applied: tuple[str, ...]
    skipped: tuple[str, ...]


def migration_files(directory):
    directory = Path(directory)
    if not directory.is_dir():
        raise MigrationError(f"Migration directory does not exist: {directory}")
    found, numbers = [], set()
    for path in directory.glob("*.sql"):
        match = re.fullmatch(r"(\d+)_[a-z][a-z0-9_]*\.sql", path.name)
        if not match:
            raise MigrationError(f"Invalid migration filename: {path.name}")
        number = int(match[1])
        if number in numbers:
            raise MigrationError(f"Duplicate migration number: {number}")
        numbers.add(number)
        found.append((number, path))
    if not found:
        raise MigrationError(f"No SQL migrations found in {directory}")
    return [path for _, path in sorted(found)]


def run_migrations(dsn, directory=MIGRATIONS_DIR, *, emit=print):
    import psycopg

    # Read all files before applying any changes; a missing/unreadable file must
    # not leave a partially loaded migration batch.
    scripts = [(path.stem, path.read_text(encoding="utf-8")) for path in migration_files(directory)]
    applied, skipped = [], []
    with psycopg.connect(dsn, autocommit=True, connect_timeout=10) as connection:
        # Session lock spans commits between migrations; another runner rechecks
        # the journal only after this connection has completed or disconnected.
        connection.execute("SELECT pg_advisory_lock(%s)", (MIGRATION_LOCK,))
        try:
            if connection.execute("SELECT to_regclass('public.api_schema_migrations')").fetchone()[0] is None:
                with connection.transaction():
                    connection.execute("""
                        CREATE TABLE public.api_schema_migrations (
                            version TEXT PRIMARY KEY,
                            applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
                        )
                    """)
            known = {row[0] for row in connection.execute("SELECT version FROM public.api_schema_migrations")}
            for version, script in scripts:
                if version in known:
                    skipped.append(version)
                    emit(f"Skipped {version}")
                    continue
                with connection.transaction():
                    connection.execute("SET LOCAL search_path = public, pg_catalog")
                    connection.execute(script, prepare=False)
                    connection.execute("INSERT INTO public.api_schema_migrations(version) VALUES (%s)", (version,))
                applied.append(version)
                known.add(version)
                emit(f"Applied {version}")
        finally:
            connection.execute("SELECT pg_advisory_unlock(%s)", (MIGRATION_LOCK,))
    return MigrationReport(tuple(applied), tuple(skipped))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database-url", default=os.environ.get("ALMOSTDONE_DATABASE_URL"),
                        help="PostgreSQL URL; defaults to ALMOSTDONE_DATABASE_URL")
    parser.add_argument("--migrations-dir", type=Path, default=MIGRATIONS_DIR)
    args = parser.parse_args(argv)
    if not args.database_url:
        parser.error("Set ALMOSTDONE_DATABASE_URL or pass --database-url")
    try:
        import psycopg
    except ImportError:
        print("Install the PostgreSQL dependencies: pip install -e './server[postgres]'", file=sys.stderr)
        return 1
    try:
        report = run_migrations(args.database_url, args.migrations_dir)
    except psycopg.Error as error:
        # Connection errors and SQL diagnostics must not expose a credential URL.
        message = error.diag.message_primary or type(error).__name__
        print(f"Migration failed: {message}", file=sys.stderr)
        return 1
    except (MigrationError, OSError, UnicodeError) as error:
        print(f"Migration failed: {error}", file=sys.stderr)
        return 1
    print(f"Migrations ready: {len(report.applied)} applied, {len(report.skipped)} skipped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
