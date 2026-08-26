#!/bin/sh
set -eu

password="$(cat /run/secrets/redis_password)"

cluster_state="$(redis-cli -h redis-node-0 -a "$password" --no-auth-warning cluster info 2>/dev/null | awk -F: '/cluster_state/ {gsub("\\r", "", $2); print $2}')"
if [ "$cluster_state" = "ok" ]; then
  echo "Redis Cluster already initialized."
  exit 0
fi

# Three-node Redis Cluster = three primaries, no replicas.
exec redis-cli -a "$password" --no-auth-warning --cluster create \
  redis-node-0:6379 \
  redis-node-1:6379 \
  redis-node-2:6379 \
  --cluster-replicas 0 \
  --cluster-yes
