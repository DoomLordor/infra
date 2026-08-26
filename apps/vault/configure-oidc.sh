#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root_dir"

: "${VAULT_TOKEN:?Set VAULT_TOKEN to an authorized Vault token}"

printf '%s\n' "$VAULT_TOKEN" | docker compose \
  --env-file "$root_dir/.env" \
  -f "$root_dir/apps/docker-compose.yaml" \
  exec -T vault sh -ec '
  IFS= read -r VAULT_TOKEN
  export VAULT_TOKEN
  exec /usr/local/bin/vault-oidc-configure.sh
'
