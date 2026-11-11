#!/usr/bin/env bash
# PostgreSQL's entrypoint runs this once, when the database volume is empty.
set -euo pipefail

init_dir=${ALMOSTDONE_DB_INIT_DIR:-/almostdone-init}
psql -X -q -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -f "$init_dir/schema.sql"

# The schema already includes server-state migration 001. The data-only dump
# clears search_path, but its COPY statements fire triggers with public lookups.
sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SET search_path TO public, pg_catalog;/" \
  "$init_dir/seed.sql" |
  psql -X -q -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"
