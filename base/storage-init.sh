#!/bin/sh
set -eu

mkdir -p \
  /data/postgres \
  /data/clickhouse \
  /data/clickhouse-logs \
  /data/redis-0 \
  /data/redis-1 \
  /data/redis-2 \
  /data/redis-standalone \
  /data/kafka \
  /data/prometheus \
  /data/traefik \
  /data/jaeger

chown 1000:1000 /data/kafka
chmod 0750 /data/kafka

chown 65534:65534 /data/prometheus
chmod 0750 /data/prometheus

chown 0:0 /data/traefik
chmod 0750 /data/traefik
touch /data/traefik/acme.json
chown 0:0 /data/traefik/acme.json
chmod 0600 /data/traefik/acme.json

chown 999:999 /data/redis-standalone
chmod 0750 /data/redis-standalone

chown 10001:0 /data/jaeger
chmod 0750 /data/jaeger
