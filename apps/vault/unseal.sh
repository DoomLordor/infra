#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
compose=(
  docker compose
  --env-file "$root_dir/.env"
  -f "$root_dir/apps/docker-compose.yaml"
)

status_value() {
  local output="$1"
  local field="$2"
  local line

  while IFS= read -r line; do
    case "$line" in
      "$field"*)
        printf '%s\n' "${line##* }"
        return 0
        ;;
    esac
  done <<< "$output"
}

set +e
status="$("${compose[@]}" exec -T vault vault status 2>&1)"
status_code=$?
set -e

initialized="$(status_value "$status" Initialized)"
sealed="$(status_value "$status" Sealed)"

if [[ "$initialized" == false ]]; then
  printf 'Vault is not initialized. Run vault operator init first.\n' >&2
  exit 1
fi

if [[ "$sealed" == false ]]; then
  printf 'Vault is already unsealed.\n'
  exit 0
fi

# `vault status` exits 2 while sealed; other failures must be surfaced.
if (( status_code != 0 && status_code != 2 )); then
  printf '%s\n' "$status" >&2
  exit "$status_code"
fi

if [[ ! -t 0 ]]; then
  printf 'Run this script from an interactive terminal.\n' >&2
  exit 1
fi

while true; do
  read -r -s -p 'Unseal key: ' unseal_key
  printf '\n'

  if [[ -z "$unseal_key" ]]; then
    printf 'An unseal key is required.\n' >&2
    continue
  fi

  if ! result="$(printf '%s\n' "$unseal_key" | "${compose[@]}" exec -T vault sh -ec '
    IFS= read -r unseal_key
    vault operator unseal "$unseal_key"
  ' 2>&1)"; then
    unset unseal_key
    printf '%s\n' "$result" >&2
    continue
  fi
  unset unseal_key

  printf '%s\n' "$result"
  if [[ "$(status_value "$result" Sealed)" == false ]]; then
    printf 'Vault is unsealed.\n'
    exit 0
  fi
done
