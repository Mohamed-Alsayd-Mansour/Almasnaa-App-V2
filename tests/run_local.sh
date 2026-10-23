#!/bin/sh
# Rebuilds a throw-away local DB, applies migrations, migrates the v1 export, runs tests.
# Usage: tests/run_local.sh path/to/almasnaa-data.json   (needs local Postgres + psycopg2; passwords below are test-only)
set -e
cd "$(dirname "$0")/.."
export SUPABASE_DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:x@localhost/almasnaa_test}"
export SEED_PASSWORD_ADMIN=test-admin SEED_PASSWORD_MANSOUR=test-m SEED_PASSWORD_QADRI=test-q SEED_PASSWORD_SAYYAD=test-s
psql "${SUPABASE_DB_URL%/*}/postgres" -qc "drop database if exists almasnaa_test" -c "create database almasnaa_test"
for f in tests/00_supabase_stub.sql supabase/migrations/0001_schema.sql supabase/migrations/0002_guards_audit_rls.sql supabase/migrations/0003_functions.sql supabase/migrations/0004_accounts_admin.sql supabase/migrations/0005_phase3_entry_guard.sql; do
  psql "$SUPABASE_DB_URL" -q -v ON_ERROR_STOP=1 -f "$f"; done
python3 scripts/migrate_v1.py --input "$1" --backup-dir /tmp/almasnaa-bk --report /tmp/almasnaa-report.json --local-test
python3 scripts/migrate_v1.py --input "$1" --backup-dir /tmp/almasnaa-bk --report /tmp/almasnaa-report.json --local-test >/dev/null   # idempotency re-run
python3 tests/test_rls.py
