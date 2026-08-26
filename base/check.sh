#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose=(docker compose --env-file "$root_dir/.env" -f "$root_dir/base/docker-compose.yaml")

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
check_one_shot redis-cluster-init
"${compose[@]}" exec -T postgres pg_isready \
  -U "${POSTGRES_USER:-app}" -d "${POSTGRES_DB:-app}"
"${compose[@]}" exec -T clickhouse clickhouse-client --query 'SELECT version()'
"${compose[@]}" exec -T redis-node-0 sh -ec \
  'redis-cli -a "$(cat /run/secrets/redis_password)" --no-auth-warning cluster info | grep cluster_state:ok'
"${compose[@]}" exec -T redis-node-0 sh -ec \
  'test "$(redis-cli -a "$(cat /run/secrets/redis_password)" --no-auth-warning cluster nodes | wc -l)" -eq 3'
"${compose[@]}" exec -T redis-standalone sh -ec \
  'redis-cli -a "$(cat /run/secrets/redis_standalone_password)" --no-auth-warning ping | grep -q PONG'
"${compose[@]}" exec -T kafka /opt/kafka/bin/kafka-broker-api-versions.sh \
  --bootstrap-server 127.0.0.1:9092 >/dev/null
"${compose[@]}" exec -T nats wget -q --spider http://127.0.0.1:8222/healthz
"${compose[@]}" exec -T jaeger wget -q --spider http://127.0.0.1:13133/status
"${compose[@]}" exec -T prometheus wget -q --spider http://127.0.0.1:9090/-/ready
"${compose[@]}" exec -T prometheus wget -q --spider http://otel-collector:8888/metrics
"${compose[@]}" exec -T traefik traefik healthcheck --ping

printf 'Base stack is healthy.\n'
