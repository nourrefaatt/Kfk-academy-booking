#!/usr/bin/env bash
# Runs the booking-rule tests against a local Postgres (not Supabase).
# Usage: PGHOST=/path/to/socket PGPORT=5499 bash tests/db/run.sh
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
P="psql -U postgres -q"
$P -c "drop database if exists kfk_test" -c "create database kfk_test" >/dev/null
$P -d kfk_test -v ON_ERROR_STOP=1 -f "$DIR/stub.sql"
$P -d kfk_test -v ON_ERROR_STOP=1 -f "$DIR/../../supabase/schema.sql" 2>&1 | grep -v NOTICE
for m in "$DIR"/../../supabase/migrations/*.sql; do $P -d kfk_test -v ON_ERROR_STOP=1 -f "$m" 2>&1 | grep -v NOTICE; done
$P -d kfk_test -f "$DIR/t1.sql" >/dev/null 2>&1
for f in t2.sql t3.sql t4.sql t5.sql t6.sql t7.sql; do $P -d kfk_test -f "$DIR/$f" 2>&1 | grep -v "^CONTEXT\|^PL/pgSQL\|^SQL statement"; done
