#!/bin/sh
set -eu

root_user="$(cat /run/secrets/minio_root_user)"
root_password="$(cat /run/secrets/minio_root_password)"
loki_secret_key="$(cat /run/secrets/loki_s3_secret_key)"

mc alias set minio http://minio:9000 "$root_user" "$root_password"
mc mb --ignore-existing minio/loki
mc admin user add minio loki "$loki_secret_key"
mc admin policy attach minio readwrite --user loki
