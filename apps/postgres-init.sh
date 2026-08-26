#!/usr/bin/env bash
set -Eeuo pipefail

export PGPASSWORD="$(< /run/secrets/postgres_password)"
grafana_password="$(< /run/secrets/grafana_db_password)"
keycloak_password="$(< /run/secrets/keycloak_db_password)"
harbor_password="$(< /run/secrets/harbor_db_password)"
gitlab_password="$(< /run/secrets/gitlab_db_password)"

psql -v ON_ERROR_STOP=1 -h postgres --username "$POSTGRES_USER" --dbname postgres \
  --set=grafana_password="$grafana_password" \
  --set=keycloak_password="$keycloak_password" \
  --set=harbor_password="$harbor_password" \
  --set=gitlab_password="$gitlab_password" <<'EOSQL'
SELECT format('CREATE ROLE grafana LOGIN PASSWORD %L', :'grafana_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grafana') \gexec
ALTER ROLE grafana PASSWORD :'grafana_password';
SELECT 'CREATE DATABASE grafana OWNER grafana'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'grafana') \gexec
ALTER DATABASE grafana OWNER TO grafana;

SELECT format('CREATE ROLE keycloak LOGIN PASSWORD %L', :'keycloak_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'keycloak') \gexec
ALTER ROLE keycloak PASSWORD :'keycloak_password';
SELECT 'CREATE DATABASE keycloak OWNER keycloak ENCODING ''UTF8'''
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'keycloak') \gexec
ALTER DATABASE keycloak OWNER TO keycloak;

SELECT format('CREATE ROLE harbor LOGIN PASSWORD %L', :'harbor_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'harbor') \gexec
ALTER ROLE harbor PASSWORD :'harbor_password';
SELECT 'CREATE DATABASE registry OWNER harbor ENCODING ''UTF8'''
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'registry') \gexec
ALTER DATABASE registry OWNER TO harbor;

SELECT format('CREATE ROLE gitlab LOGIN PASSWORD %L', :'gitlab_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gitlab') \gexec
ALTER ROLE gitlab PASSWORD :'gitlab_password';
SELECT 'CREATE DATABASE gitlabhq_production OWNER gitlab ENCODING ''UTF8'''
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'gitlabhq_production') \gexec
ALTER DATABASE gitlabhq_production OWNER TO gitlab;
EOSQL

psql -v ON_ERROR_STOP=1 -h postgres --username "$POSTGRES_USER" --dbname registry <<'EOSQL'
ALTER SCHEMA public OWNER TO harbor;
GRANT ALL ON SCHEMA public TO harbor;
EOSQL

psql -v ON_ERROR_STOP=1 -h postgres --username "$POSTGRES_USER" \
  --dbname gitlabhq_production <<'EOSQL'
CREATE EXTENSION IF NOT EXISTS amcheck;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
EOSQL
