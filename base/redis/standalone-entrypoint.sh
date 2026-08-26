#!/bin/sh
set -eu

password="$(cat /run/secrets/redis_standalone_password)"
maxmemory="${REDIS_STANDALONE_MAXMEMORY:-768mb}"

umask 077
cp /usr/local/etc/redis/redis.conf /tmp/redis.conf
cat >> /tmp/redis.conf <<EOCONF
requirepass ${password}
maxmemory ${maxmemory}
EOCONF
chown 999:999 /tmp/redis.conf

exec /usr/local/bin/docker-entrypoint.sh redis-server /tmp/redis.conf
