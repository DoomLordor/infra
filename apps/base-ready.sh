#!/usr/bin/env bash
set -Eeuo pipefail

wait_for() {
  local name="$1"
  shift
  local attempt

  for ((attempt = 1; attempt <= 120; attempt++)); do
    if "$@" >/dev/null 2>&1; then
      printf '%s is ready.\n' "$name"
      return 0
    fi
    sleep 2
  done

  printf 'Timed out waiting for %s.\n' "$name" >&2
  return 1
}

tcp_ready() {
  local host="$1"
  local port="$2"
  exec 3<>"/dev/tcp/${host}/${port}" || return 1
  exec 3>&-
}

http_ready() {
  local host="$1"
  local port="$2"
  local path="$3"
  local status

  exec 3<>"/dev/tcp/${host}/${port}" || return 1
  printf 'GET %s HTTP/1.0\r\nHost: %s\r\n\r\n' "$path" "$host" >&3
  IFS= read -r status <&3
  exec 3>&-
  [[ "$status" == *" 200 "* ]]
}

wait_for PostgreSQL pg_isready -h postgres -p 5432 -U "${POSTGRES_USER}"
wait_for Redis tcp_ready redis-standalone 6379
wait_for Loki http_ready loki 3100 /ready
wait_for Prometheus http_ready prometheus 9090 /-/ready
wait_for Jaeger http_ready jaeger 13133 /status
wait_for Traefik http_ready traefik 8080 /ping
