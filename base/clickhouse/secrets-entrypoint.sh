#!/usr/bin/env bash
set -Eeuo pipefail

admin_secret=/run/secrets/clickhouse_admin_password
app_secret=/run/secrets/clickhouse_app_password
password_config=/etc/clickhouse-server/users.d/zz-passwords.xml

for secret in "$admin_secret" "$app_secret"; do
  if [[ ! -s "$secret" ]]; then
    printf 'Missing or empty ClickHouse secret: %s\n' "$secret" >&2
    exit 1
  fi
done

admin_hash="$(tr -d '\n' < "$admin_secret" | sha256sum | cut -d' ' -f1)"
app_hash="$(tr -d '\n' < "$app_secret" | sha256sum | cut -d' ' -f1)"

umask 077
tmp_config="$(mktemp /etc/clickhouse-server/users.d/.zz-passwords.xml.XXXXXX)"
trap 'rm -f "$tmp_config"' EXIT

cat > "$tmp_config" <<EOF
<clickhouse>
    <users>
        <admin>
            <password_sha256_hex hide_in_preprocessed="true">$admin_hash</password_sha256_hex>
        </admin>
        <app>
            <password_sha256_hex hide_in_preprocessed="true">$app_hash</password_sha256_hex>
        </app>
    </users>
</clickhouse>
EOF

chown "$(id -u clickhouse):$(id -g clickhouse)" "$tmp_config"
chmod 0400 "$tmp_config"
mv -f "$tmp_config" "$password_config"
trap - EXIT

exec /entrypoint.sh "$@"
