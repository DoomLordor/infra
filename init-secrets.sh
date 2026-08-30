#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
secrets_dir="$root_dir/secrets"
env_file="$root_dir/.env"
env_example="$root_dir/.env.example"

mkdir -p "$secrets_dir"
chmod 700 "$secrets_dir"

random_secret() {
  openssl rand -base64 48 | tr -d '\n'
}

write_secret_if_missing() {
  local path="$1"
  if [[ ! -s "$path" ]]; then
    umask 077
    random_secret > "$path"
    printf '\n' >> "$path"
  fi
  chmod 600 "$path"
}

write_hex_secret_if_missing() {
  local path="$1"
  local length="$2"
  if [[ ! -s "$path" ]]; then
    umask 077
    openssl rand -hex "$((length / 2))" | tr -d '\n' > "$path"
  fi
  chmod 600 "$path"
}

write_binary_secret_if_missing() {
  local path="$1"
  local length="$2"
  if [[ ! -s "$path" ]]; then
    umask 077
    openssl rand "$length" > "$path"
  fi
  chmod 600 "$path"
}

legacy_clickhouse_credentials="$secrets_dir/clickhouse-credentials.txt"
if [[ -f "$legacy_clickhouse_credentials" ]]; then
  while IFS='=' read -r key value; do
    case "$key" in
      CLICKHOUSE_ADMIN_PASSWORD)
        if [[ ! -s "$secrets_dir/clickhouse_admin_password" ]]; then
          umask 077
          printf '%s\n' "$value" > "$secrets_dir/clickhouse_admin_password"
        fi
        ;;
      CLICKHOUSE_APP_PASSWORD)
        if [[ ! -s "$secrets_dir/clickhouse_app_password" ]]; then
          umask 077
          printf '%s\n' "$value" > "$secrets_dir/clickhouse_app_password"
        fi
        ;;
    esac
  done < "$legacy_clickhouse_credentials"
fi

for name in \
  postgres_password \
  postgres_monitor_password \
  grafana_db_password \
  redis_password \
  grafana_admin_password \
  clickhouse_admin_password \
  clickhouse_app_password \
  keycloak_db_password \
  keycloak_admin_password
do
  write_secret_if_missing "$secrets_dir/$name"
done

write_hex_secret_if_missing "$secrets_dir/harbor_db_password" 64
write_hex_secret_if_missing "$secrets_dir/minio_root_user" 32
write_hex_secret_if_missing "$secrets_dir/minio_root_password" 64
write_hex_secret_if_missing "$secrets_dir/loki_s3_secret_key" 64
write_hex_secret_if_missing "$secrets_dir/harbor_admin_password" 32
write_hex_secret_if_missing "$secrets_dir/harbor_core_secret" 16
write_hex_secret_if_missing "$secrets_dir/harbor_jobservice_secret" 16
write_hex_secret_if_missing "$secrets_dir/harbor_registry_password" 32
write_hex_secret_if_missing "$secrets_dir/harbor_registry_http_secret" 32
write_hex_secret_if_missing "$secrets_dir/harbor_csrf_key" 32
write_hex_secret_if_missing "$secrets_dir/harbor_reload_key" 32
write_hex_secret_if_missing "$secrets_dir/harbor_secret_key" 16
write_hex_secret_if_missing "$secrets_dir/gitlab_db_password" 64
write_hex_secret_if_missing "$secrets_dir/redis_standalone_password" 64
write_hex_secret_if_missing "$secrets_dir/gitlab_root_password" 32
write_hex_secret_if_missing "$secrets_dir/gitlab_oidc_client_secret" 64
write_hex_secret_if_missing "$secrets_dir/grafana_oidc_client_secret" 64
write_hex_secret_if_missing "$secrets_dir/harbor_oidc_client_secret" 64
write_hex_secret_if_missing "$secrets_dir/vault_oidc_client_secret" 64
write_hex_secret_if_missing "$secrets_dir/oauth2_proxy_client_secret" 64
write_hex_secret_if_missing "$secrets_dir/keycloak_bootstrap_client_secret" 64
write_binary_secret_if_missing "$secrets_dir/oauth2_proxy_cookie_secret" 32

harbor_private_key="$secrets_dir/harbor_core_private_key.pem"
harbor_root_cert="$secrets_dir/harbor_registry_root.crt"
if [[ ! -e "$harbor_private_key" && ! -e "$harbor_root_cert" ]]; then
  umask 077
  openssl genrsa -out "$harbor_private_key" 4096
  openssl req -x509 -new -sha256 \
    -key "$harbor_private_key" \
    -days 3650 \
    -subj '/CN=harbor-token-service' \
    -out "$harbor_root_cert"
elif [[ ! -s "$harbor_private_key" || ! -s "$harbor_root_cert" ]]; then
  printf 'Harbor token key pair is incomplete in %s\n' "$secrets_dir" >&2
  exit 1
fi

harbor_registry_password="$(< "$secrets_dir/harbor_registry_password")"
harbor_registry_passwd_tmp="$secrets_dir/harbor_registry_passwd.tmp"
if ! printf '%s\n' "$harbor_registry_password" | docker run --rm -i \
  --entrypoint htpasswd httpd:2.4.68-alpine \
  -niB harbor_registry_user > "$harbor_registry_passwd_tmp"
then
  rm -f "$harbor_registry_passwd_tmp"
  exit 1
fi
mv "$harbor_registry_passwd_tmp" "$secrets_dir/harbor_registry_passwd"

if [[ ! -f "$env_file" ]]; then
  cp "$env_example" "$env_file"
fi

chmod 600 "$env_file"

keycloak_db_password="$(< "$secrets_dir/keycloak_db_password")"
keycloak_admin_password="$(< "$secrets_dir/keycloak_admin_password")"
{
  printf 'db-password=%s\n' "$keycloak_db_password"
  printf 'bootstrap-admin-password=%s\n' "$keycloak_admin_password"
} > "$secrets_dir/keycloak.conf"

harbor_db_password="$(< "$secrets_dir/harbor_db_password")"
harbor_admin_password="$(< "$secrets_dir/harbor_admin_password")"
redis_standalone_password="$(< "$secrets_dir/redis_standalone_password")"
harbor_core_secret="$(< "$secrets_dir/harbor_core_secret")"
harbor_jobservice_secret="$(< "$secrets_dir/harbor_jobservice_secret")"
harbor_registry_http_secret="$(< "$secrets_dir/harbor_registry_http_secret")"
harbor_csrf_key="$(< "$secrets_dir/harbor_csrf_key")"
harbor_reload_key="$(< "$secrets_dir/harbor_reload_key")"

{
  printf '_REDIS_URL_CORE=redis://:%s@redis-standalone:6379?idle_timeout_seconds=30\n' "$redis_standalone_password"
  printf '_REDIS_URL_REG=redis://:%s@redis-standalone:6379/1?idle_timeout_seconds=30\n' "$redis_standalone_password"
  printf 'POSTGRESQL_PASSWORD=%s\n' "$harbor_db_password"
  printf 'HARBOR_ADMIN_PASSWORD=%s\n' "$harbor_admin_password"
  printf 'CORE_SECRET=%s\n' "$harbor_core_secret"
  printf 'JOBSERVICE_SECRET=%s\n' "$harbor_jobservice_secret"
  printf 'RELOAD_KEY=%s\n' "$harbor_reload_key"
  printf 'REGISTRY_CREDENTIAL_PASSWORD=%s\n' "$harbor_registry_password"
  printf 'CSRF_KEY=%s\n' "$harbor_csrf_key"
} > "$secrets_dir/harbor-core.env"

{
  printf 'CORE_SECRET=%s\n' "$harbor_core_secret"
  printf 'JOBSERVICE_SECRET=%s\n' "$harbor_jobservice_secret"
  printf 'REGISTRY_CREDENTIAL_PASSWORD=%s\n' "$harbor_registry_password"
} > "$secrets_dir/harbor-jobservice.env"

{
  printf 'CORE_SECRET=%s\n' "$harbor_core_secret"
  printf 'JOBSERVICE_SECRET=%s\n' "$harbor_jobservice_secret"
} > "$secrets_dir/harbor-registryctl.env"

{
  printf 'SCANNER_REDIS_URL=redis://:%s@redis-standalone:6379/5?idle_timeout_seconds=30\n' "$redis_standalone_password"
  printf 'SCANNER_STORE_REDIS_URL=redis://:%s@redis-standalone:6379/5?idle_timeout_seconds=30\n' "$redis_standalone_password"
  printf 'SCANNER_JOB_QUEUE_REDIS_URL=redis://:%s@redis-standalone:6379/5?idle_timeout_seconds=30\n' "$redis_standalone_password"
} > "$secrets_dir/harbor-trivy.env"

{
  printf 'HARBOR_REDIS_URL=redis://:%s@redis-standalone:6379/2?idle_timeout_seconds=30\n' "$redis_standalone_password"
  printf 'HARBOR_DATABASE_PASSWORD=%s\n' "$harbor_db_password"
} > "$secrets_dir/harbor-exporter.env"

cat > "$secrets_dir/harbor-jobservice-config.yml" <<EOF2
protocol: http
port: 8080
worker_pool:
  workers: 10
  backend: redis
  redis_pool:
    redis_url: redis://:${redis_standalone_password}@redis-standalone:6379/2?idle_timeout_seconds=30
    namespace: harbor_job_service_namespace
    idle_timeout_second: 3600
job_loggers:
  - name: STD_OUTPUT
    level: INFO
  - name: FILE
    level: INFO
    settings:
      base_dir: /var/log/jobs
    sweeper:
      duration: 14
      settings:
        work_dir: /var/log/jobs
loggers:
  - name: STD_OUTPUT
    level: INFO
metric:
  enabled: true
  path: /metrics
  port: 9090
reaper:
  max_update_hours: 24
  max_dangling_hours: 168
max_retrieve_size_mb: 10
EOF2

cat > "$secrets_dir/harbor-registry-config.yml" <<EOF2
version: 0.1
log:
  level: info
  fields:
    service: registry
storage:
  cache:
    layerinfo: redis
  filesystem:
    rootdirectory: /storage
  maintenance:
    uploadpurging:
      enabled: true
      age: 168h
      interval: 24h
      dryrun: false
  delete:
    enabled: true
redis:
  addr: redis-standalone:6379
  readtimeout: 10s
  writetimeout: 10s
  dialtimeout: 10s
  password: ${redis_standalone_password}
  username: ""
  db: 1
  enableTLS: false
  pool:
    maxidle: 100
    maxactive: 500
    idletimeout: 60s
http:
  addr: :5000
  secret: ${harbor_registry_http_secret}
  debug:
    addr: :9090
    prometheus:
      enabled: true
      path: /metrics
auth:
  htpasswd:
    realm: harbor-registry-basic-realm
    path: /etc/registry/passwd
validation:
  disabled: true
compatibility:
  schema1:
    enabled: true
EOF2

# Local Compose bind-mounts secret sources, so non-root service users need read access.
# The parent secrets directory remains mode 0700 on the host.
chmod 644 \
  "$secrets_dir/postgres_password" \
  "$secrets_dir/postgres_monitor_password" \
  "$secrets_dir/grafana_db_password" \
  "$secrets_dir/grafana_admin_password" \
  "$secrets_dir/redis_password" \
  "$secrets_dir/clickhouse_admin_password" \
  "$secrets_dir/clickhouse_app_password" \
  "$secrets_dir/keycloak_db_password" \
  "$secrets_dir/harbor_db_password" \
  "$secrets_dir/harbor_admin_password" \
  "$secrets_dir/gitlab_db_password" \
  "$secrets_dir/redis_standalone_password" \
  "$secrets_dir/gitlab_root_password" \
  "$secrets_dir/gitlab_oidc_client_secret" \
  "$secrets_dir/grafana_oidc_client_secret" \
  "$secrets_dir/harbor_oidc_client_secret" \
  "$secrets_dir/vault_oidc_client_secret" \
  "$secrets_dir/oauth2_proxy_client_secret" \
  "$secrets_dir/keycloak_bootstrap_client_secret" \
  "$secrets_dir/oauth2_proxy_cookie_secret" \
  "$secrets_dir/keycloak.conf" \
  "$harbor_private_key" \
  "$harbor_root_cert" \
  "$secrets_dir/harbor_secret_key" \
  "$secrets_dir/harbor_registry_passwd" \
  "$secrets_dir/harbor-jobservice-config.yml" \
  "$secrets_dir/harbor-registry-config.yml"
chmod 600 \
  "$secrets_dir/minio_root_user" \
  "$secrets_dir/minio_root_password" \
  "$secrets_dir/loki_s3_secret_key" \
  "$secrets_dir/harbor-core.env" \
  "$secrets_dir/harbor-jobservice.env" \
  "$secrets_dir/harbor-registryctl.env" \
  "$secrets_dir/harbor-trivy.env" \
  "$secrets_dir/harbor-exporter.env"

# OTel Collector's config provider reads env vars. This file is gitignored and mode 0600.
{
  printf 'POSTGRES_MONITOR_PASSWORD=%s\n' "$(tr -d '\n' < "$secrets_dir/postgres_monitor_password")"
  printf 'REDIS_PASSWORD=%s\n' "$(tr -d '\n' < "$secrets_dir/redis_password")"
} > "$secrets_dir/otel.env"
chmod 600 "$secrets_dir/otel.env"

{
  printf 'LOKI_S3_ACCESS_KEY=loki\n'
  printf 'LOKI_S3_SECRET_ACCESS_KEY=%s\n' "$(tr -d '\n' < "$secrets_dir/loki_s3_secret_key")"
} > "$secrets_dir/loki.env"
chmod 600 "$secrets_dir/loki.env"

cat <<EOF2
Secrets initialized.

ClickHouse credentials:
  $secrets_dir/clickhouse_admin_password
  $secrets_dir/clickhouse_app_password

Initial web credentials:
  Keycloak admin: $secrets_dir/keycloak_admin_password
  Harbor admin:   $secrets_dir/harbor_admin_password
  GitLab root:    $secrets_dir/gitlab_root_password

Next:
  1. Edit SERVER_NAME, DATA_ROOT, LAN_BIND_IP and step-ca settings in .env.
  2. Copy your step-ca root certificate to base/traefik/certs/root_ca.crt.
  3. Store the generated credentials in your password manager.
  4. Start base: docker compose --env-file .env -f base/docker-compose.yaml up -d --wait
  5. Start apps: docker compose --env-file .env -f apps/docker-compose.yaml up -d
EOF2
