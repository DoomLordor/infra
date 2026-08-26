#!/usr/bin/env bash
set -Eeuo pipefail

kcadm=/opt/keycloak/bin/kcadm.sh
server_name="${SERVER_NAME:?SERVER_NAME is required}"
realm="${KEYCLOAK_REALM:?KEYCLOAK_REALM is required}"

export HOME=/tmp
mkdir -p /tmp/.keycloak

export KC_CLI_CLIENT_SECRET="$(< /run/secrets/keycloak_bootstrap_client_secret)"
if "$kcadm" config credentials \
  --server http://keycloak:8080 \
  --realm "$realm" \
  --client infra-bootstrap \
  --config /tmp/kcadm.config >/dev/null 2>&1
then
  printf 'Authenticated with the Keycloak infra-bootstrap service account.\n'
  unset KC_CLI_CLIENT_SECRET
else
  unset KC_CLI_CLIENT_SECRET
  rm -f /tmp/kcadm.config
  export KC_CLI_PASSWORD="$(< /run/secrets/keycloak_admin_password)"
  "$kcadm" config credentials \
    --server http://keycloak:8080 \
    --realm master \
    --user admin \
    --config /tmp/kcadm.config >/dev/null
  unset KC_CLI_PASSWORD
fi

if ! "$kcadm" get "realms/${realm}" --config /tmp/kcadm.config >/dev/null 2>&1; then
  printf 'Keycloak realm %s does not exist; check startup realm import.\n' "$realm" >&2
  exit 1
fi

groups_scope_payload=/tmp/groups-scope.json
cat > "$groups_scope_payload" <<'EOF'
{
  "name": "groups",
  "description": "Full Keycloak group paths for application authorization",
  "protocol": "openid-connect",
  "attributes": {
    "include.in.token.scope": "true",
    "display.on.consent.screen": "false"
  }
}
EOF

groups_scope_id="$("$kcadm" get client-scopes -r "$realm" \
  --fields id,name --format csv --noquotes --config /tmp/kcadm.config |
  while IFS=, read -r id name; do
    if [[ "$name" == "groups" ]]; then
      printf '%s' "$id"
      break
    fi
  done)"

if [[ -z "$groups_scope_id" ]]; then
  "$kcadm" create client-scopes -r "$realm" -f "$groups_scope_payload" \
    --config /tmp/kcadm.config >/dev/null
  groups_scope_id="$("$kcadm" get client-scopes -r "$realm" \
    --fields id,name --format csv --noquotes --config /tmp/kcadm.config |
    while IFS=, read -r id name; do
      if [[ "$name" == "groups" ]]; then
        printf '%s' "$id"
        break
      fi
  done)"
fi

"$kcadm" update "client-scopes/${groups_scope_id}" -r "$realm" \
  -f "$groups_scope_payload" --config /tmp/kcadm.config >/dev/null

groups_mapper_payload=/tmp/groups-mapper.json
cat > "$groups_mapper_payload" <<'EOF'
{
  "name": "groups",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-group-membership-mapper",
  "consentRequired": false,
  "config": {
    "claim.name": "groups",
    "full.path": "true",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "userinfo.token.claim": "true"
  }
}
EOF

groups_mapper_id="$("$kcadm" get \
  "client-scopes/${groups_scope_id}/protocol-mappers/models" -r "$realm" \
  --fields id,name --format csv --noquotes --config /tmp/kcadm.config |
  while IFS=, read -r id name; do
    if [[ "$name" == "groups" ]]; then
      printf '%s' "$id"
      break
    fi
  done)"

if [[ -n "$groups_mapper_id" ]]; then
  "$kcadm" delete \
    "client-scopes/${groups_scope_id}/protocol-mappers/models/${groups_mapper_id}" \
    -r "$realm" --config /tmp/kcadm.config >/dev/null
fi
"$kcadm" create "client-scopes/${groups_scope_id}/protocol-mappers/models" \
  -r "$realm" -f "$groups_mapper_payload" --config /tmp/kcadm.config >/dev/null

existing_groups="$("$kcadm" get groups -r "$realm" --fields name \
  --format csv --noquotes --config /tmp/kcadm.config)"
for group in \
  grafana-viewers \
  grafana-editors \
  grafana-admins \
  harbor-users \
  harbor-admins \
  vault-users \
  vault-admins \
  observability
do
  if ! printf '%s\n' "$existing_groups" | grep -Fxq "$group"; then
    "$kcadm" create groups -r "$realm" -s "name=${group}" \
      --config /tmp/kcadm.config >/dev/null
  fi
done

reconcile_client() {
  local client_id="$1"
  local secret_file="$2"
  local redirect_uris="$3"
  local web_origin="$4"
  local protocol_mappers="${5:-[]}"
  local secret client_uuid payload

  secret="$(< "$secret_file")"
  payload="/tmp/${client_id}.json"

  cat > "$payload" <<EOF
{
  "clientId": "${client_id}",
  "name": "${client_id}",
  "enabled": true,
  "protocol": "openid-connect",
  "publicClient": false,
  "clientAuthenticatorType": "client-secret",
  "secret": "${secret}",
  "standardFlowEnabled": true,
  "implicitFlowEnabled": false,
  "directAccessGrantsEnabled": false,
  "serviceAccountsEnabled": false,
  "frontchannelLogout": true,
  "redirectUris": ${redirect_uris},
  "webOrigins": ["${web_origin}"],
  "defaultClientScopes": ["web-origins", "acr", "profile", "roles", "basic", "email", "groups"],
  "optionalClientScopes": ["address", "phone", "offline_access", "microprofile-jwt"],
  "protocolMappers": ${protocol_mappers},
  "attributes": {
    "pkce.code.challenge.method": "S256",
    "post.logout.redirect.uris": "${web_origin}/*"
  }
}
EOF

  client_uuid="$("$kcadm" get clients -r "$realm" -q "clientId=${client_id}" \
    --fields id --format csv --noquotes --config /tmp/kcadm.config | tr -d '\r' | sed -n '1p')"

  if [[ -n "$client_uuid" ]]; then
    "$kcadm" update "clients/${client_uuid}" -r "$realm" -f "$payload" \
      --config /tmp/kcadm.config >/dev/null
  else
    "$kcadm" create clients -r "$realm" -f "$payload" \
      --config /tmp/kcadm.config >/dev/null
  fi
}

reconcile_client \
  gitlab \
  /run/secrets/gitlab_oidc_client_secret \
  "[\"https://gitlab.${server_name}/users/auth/openid_connect/callback\"]" \
  "https://gitlab.${server_name}"

reconcile_client \
  grafana \
  /run/secrets/grafana_oidc_client_secret \
  "[\"https://grafana.${server_name}/login/generic_oauth\"]" \
  "https://grafana.${server_name}"

reconcile_client \
  harbor \
  /run/secrets/harbor_oidc_client_secret \
  "[\"https://harbor.${server_name}/c/oidc/callback\"]" \
  "https://harbor.${server_name}"

reconcile_client \
  vault \
  /run/secrets/vault_oidc_client_secret \
  "[\"https://vault.${server_name}/ui/vault/auth/oidc/oidc/callback\",\"http://localhost:8250/oidc/callback\"]" \
  "https://vault.${server_name}"

oauth2_proxy_mappers='[
  {
    "name": "oauth2-proxy-audience",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-audience-mapper",
    "consentRequired": false,
    "config": {
      "included.client.audience": "infra-forward-auth",
      "id.token.claim": "true",
      "access.token.claim": "true"
    }
  }
]'

reconcile_client \
  infra-forward-auth \
  /run/secrets/oauth2_proxy_client_secret \
  "[\"https://oauth.${server_name}/oauth2/callback\"]" \
  "https://oauth.${server_name}" \
  "$oauth2_proxy_mappers"

bootstrap_secret="$(< /run/secrets/keycloak_bootstrap_client_secret)"
bootstrap_payload=/tmp/infra-bootstrap.json
cat > "$bootstrap_payload" <<EOF
{
  "clientId": "infra-bootstrap",
  "name": "Infrastructure configuration reconciler",
  "enabled": true,
  "protocol": "openid-connect",
  "publicClient": false,
  "clientAuthenticatorType": "client-secret",
  "secret": "${bootstrap_secret}",
  "standardFlowEnabled": false,
  "implicitFlowEnabled": false,
  "directAccessGrantsEnabled": false,
  "serviceAccountsEnabled": true
}
EOF

bootstrap_uuid="$("$kcadm" get clients -r "$realm" -q clientId=infra-bootstrap \
  --fields id --format csv --noquotes --config /tmp/kcadm.config |
  tr -d '\r' | sed -n '1p')"
if [[ -n "$bootstrap_uuid" ]]; then
  "$kcadm" update "clients/${bootstrap_uuid}" -r "$realm" -f "$bootstrap_payload" \
    --config /tmp/kcadm.config >/dev/null
else
  "$kcadm" create clients -r "$realm" -f "$bootstrap_payload" \
    --config /tmp/kcadm.config >/dev/null
fi

"$kcadm" add-roles -r "$realm" \
  --uusername service-account-infra-bootstrap \
  --cclientid realm-management \
  --rolename realm-admin \
  --config /tmp/kcadm.config >/dev/null

printf 'Keycloak realm %s clients reconciled.\n' "$realm"
