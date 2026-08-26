#!/bin/sh
set -eu

server_name="${SERVER_NAME:?SERVER_NAME is required}"
realm="${KEYCLOAK_REALM:?KEYCLOAK_REALM is required}"
admin_password="$(cat /run/secrets/harbor_admin_password)"
client_secret="$(cat /run/secrets/harbor_oidc_client_secret)"
payload=/tmp/harbor-oidc.json

cat > "$payload" <<EOF
{
  "auth_mode": "oidc_auth",
  "primary_auth_mode": true,
  "oidc_name": "Keycloak",
  "oidc_endpoint": "https://keycloak.${server_name}/realms/${realm}",
  "oidc_client_id": "harbor",
  "oidc_client_secret": "${client_secret}",
  "oidc_groups_claim": "groups",
  "oidc_admin_group": "/harbor-admins",
  "oidc_group_filter": "^/harbor-.*$",
  "oidc_scope": "openid,profile,email,groups,offline_access",
  "oidc_user_claim": "preferred_username",
  "oidc_verify_cert": true,
  "oidc_auto_onboard": true,
  "oidc_logout": true,
  "project_creation_restriction": "adminonly"
}
EOF

status="$(curl -sS -o /tmp/harbor-oidc-response -w '%{http_code}' \
  -u "admin:${admin_password}" \
  -H 'Content-Type: application/json' \
  -X PUT \
  --data-binary "@${payload}" \
  http://harbor-core:8080/api/v2.0/configurations)"

case "$status" in
  200|201|204)
    printf 'Harbor OIDC configuration reconciled.\n'
    ;;
  *)
    printf 'Harbor OIDC configuration failed with HTTP %s: ' "$status" >&2
    cat /tmp/harbor-oidc-response >&2
    printf '\n' >&2
    exit 1
    ;;
esac
