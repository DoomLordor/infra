#!/usr/bin/env bash
set -Eeuo pipefail

monitor_password="$(cat /run/secrets/postgres_monitor_password)"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
  --set=monitor_password="$monitor_password" <<'EOSQL'
SELECT format('CREATE ROLE otel_monitor LOGIN PASSWORD %L', :'monitor_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'otel_monitor') \gexec
ALTER ROLE otel_monitor PASSWORD :'monitor_password';
GRANT pg_monitor TO otel_monitor;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'EOSQL'
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
EOSQL
