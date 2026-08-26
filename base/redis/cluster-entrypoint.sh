#!/bin/sh
set -eu

announce_hostname="${1:?announce hostname is required}"
password="$(cat /run/secrets/redis_password)"
maxmemory="${REDIS_MAXMEMORY:-512mb}"

umask 077
cp /usr/local/etc/redis/redis.conf /tmp/redis.conf
cat >> /tmp/redis.conf <<EOCONF
requirepass ${password}
masterauth ${password}
cluster-announce-hostname ${announce_hostname}
maxmemory ${maxmemory}
EOCONF

# Re-enter the official Redis entrypoint so it can fix bind-mount ownership
# and drop privileges before starting redis-server.
exec /usr/local/bin/docker-entrypoint.sh redis-server /tmp/redis.conf
