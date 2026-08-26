#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose=(docker compose --env-file "$root_dir/.env" -f "$root_dir/apps/docker-compose.yaml")

set -a
# shellcheck disable=SC1091
source "$root_dir/.env"
set +a

check_one_shot() {
  local service="$1"
  local container_id
  container_id="$("${compose[@]}" ps -aq "$service")"
  test -n "$container_id"
  test "$(docker inspect --format '{{.State.Status}}' "$container_id")" = exited
  test "$(docker inspect --format '{{.State.ExitCode}}' "$container_id")" -eq 0
}

"${compose[@]}" config --quiet
check_one_shot storage-init
check_one_shot base-ready
check_one_shot postgres-init
check_one_shot keycloak-bootstrap
check_one_shot harbor-oidc-init
"${compose[@]}" exec -T vault vault status >/dev/null
"${compose[@]}" exec -T keycloak bash -ec \
  "{ printf 'HEAD /health/ready HTTP/1.0\\r\\n\\r\\n' >&0; grep -q 'HTTP/1.0 200'; } 0<>/dev/tcp/127.0.0.1/9000"
"${compose[@]}" exec -T keycloak bash -ec \
  "{ printf 'GET /realms/%s/.well-known/openid-configuration HTTP/1.0\\r\\nHost: keycloak\\r\\n\\r\\n' \"\$KEYCLOAK_REALM\" >&0; grep -Eq 'HTTP/1.[01] 200'; } 0<>/dev/tcp/127.0.0.1/8080"
"${compose[@]}" exec -T harbor-core curl -fsS \
  http://127.0.0.1:8080/api/v2.0/health >/dev/null
"${compose[@]}" exec -T gitlab curl -fSs --max-time 10 \
  -H "Host: gitlab.${SERVER_NAME}" http://127.0.0.1/-/readiness?all=1 >/dev/null
"${compose[@]}" exec -T grafana sh -ec \
  "wget -q -O- http://127.0.0.1:3000/api/health | grep -q '\"database\": \"ok\"'"
"${compose[@]}" exec -T grafana wget -q --spider http://oauth2-proxy:4180/ping

test -s "$root_dir/base/traefik/certs/root_ca.crt"
curl --cacert "$root_dir/base/traefik/certs/root_ca.crt" -fsS \
  "https://harbor.${SERVER_NAME}/api/v2.0/health" >/dev/null
for host in jaeger prometheus; do
  test "$(curl --cacert "$root_dir/base/traefik/certs/root_ca.crt" \
    -sS -o /dev/null -w '%{http_code}' "https://${host}.${SERVER_NAME}/")" -eq 302
done

printf 'Apps stack is healthy.\n'
