#!/bin/sh
set -eu

server_name="${SERVER_NAME:?SERVER_NAME is required}"
realm="${KEYCLOAK_REALM:?KEYCLOAK_REALM is required}"
client_secret="$(cat /run/secrets/vault_oidc_client_secret)"

if ! vault auth list -format=json | grep -q '"oidc/"'; then
  vault auth enable -path=oidc oidc
fi

vault write auth/oidc/config \
  oidc_discovery_url="https://keycloak.${server_name}/realms/${realm}" \
  oidc_discovery_ca_pem=@/etc/step-ca/root_ca.crt \
  oidc_client_id=vault \
  oidc_client_secret="$client_secret" \
  default_role=default >/dev/null

cat > /tmp/vault-oidc-role.json <<EOF
{
  "role_type": "oidc",
  "user_claim": "sub",
  "groups_claim": "groups",
  "bound_audiences": ["vault"],
  "oidc_scopes": ["profile", "email", "groups"],
  "allowed_redirect_uris": [
    "https://vault.${server_name}/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ],
  "bound_claims": {
    "groups": ["/vault-users", "/vault-admins"]
  },
  "token_policies": ["default"],
  "token_ttl": "1h"
}
EOF
vault write auth/oidc/role/default @/tmp/vault-oidc-role.json >/dev/null

vault policy write vault-admin /vault/policies/admin.hcl >/dev/null

mount_accessor="$(vault read -field=accessor sys/auth/oidc)"
group_id="$(vault read -field=id identity/group/name/vault-admins 2>/dev/null || true)"
if [ -z "$group_id" ]; then
  group_id="$(vault write -field=id identity/group name=vault-admins type=external policies=vault-admin)"
else
  vault write "identity/group/id/${group_id}" \
    name=vault-admins \
    type=external \
    policies=vault-admin >/dev/null
fi

alias_group_id="$(vault write -field=id identity/lookup/group \
  alias_name=/vault-admins \
  alias_mount_accessor="$mount_accessor" 2>/dev/null || true)"
if [ "$alias_group_id" != "$group_id" ]; then
  vault write identity/group-alias \
    name=/vault-admins \
    mount_accessor="$mount_accessor" \
    canonical_id="$group_id" >/dev/null
fi

printf 'Vault OIDC configuration reconciled.\n'
