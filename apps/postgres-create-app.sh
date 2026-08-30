#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -ne 1 || ! "$1" =~ ^[a-z][a-z0-9_]{0,62}$ ]]; then
  printf 'Usage: %s <application-name>\n' "${BASH_SOURCE[0]}" >&2
  printf 'Application name must start with a lowercase letter and contain only lowercase letters, digits, and underscores.\n' >&2
  exit 2
fi

app_name="$1"
password_file="$root_dir/secrets/${app_name}_db_password"
compose=(docker compose --env-file "$root_dir/.env" -f "$root_dir/base/docker-compose.yaml")

if [[ ! -f "$root_dir/.env" ]]; then
  printf 'Missing %s. Create it from .env.example first.\n' "$root_dir/.env" >&2
  exit 1
fi

mkdir -p "$root_dir/secrets"
chmod 700 "$root_dir/secrets"

if [[ ! -s "$password_file" ]]; then
  umask 077
  openssl rand -hex 32 > "$password_file"
fi

# Compose bind-mounts secret files, so application containers may need to read them.
chmod 644 "$password_file"
app_password="$(< "$password_file")"

"${compose[@]}" exec -T postgres bash -ceu '
  export PGPASSWORD="$(< /run/secrets/postgres_password)"
  psql --username "$POSTGRES_USER" --dbname postgres --set=ON_ERROR_STOP=1
' <<EOSQL
SELECT format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD %L', '${app_name}', '${app_password}')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${app_name}') \gexec
SELECT format('ALTER ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD %L', '${app_name}', '${app_password}') \gexec
SELECT format('CREATE DATABASE %I OWNER %I ENCODING ''UTF8''', '${app_name}', '${app_name}')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '${app_name}') \gexec
SELECT format('ALTER DATABASE %I OWNER TO %I', '${app_name}', '${app_name}') \gexec
EOSQL

printf 'PostgreSQL role and database %q are ready. Password: %s\n' "$app_name" "$password_file"
