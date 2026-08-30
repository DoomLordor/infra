#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
base=(docker compose --env-file "$root_dir/.env" -f "$root_dir/base/docker-compose.yaml")
apps=(docker compose --profile ci --env-file "$root_dir/.env" -f "$root_dir/apps/docker-compose.yaml")

if [[ ! -s "$root_dir/secrets/gitlab_runner_token" ]]; then
  printf 'Create secrets/gitlab_runner_token before starting the CI runner.\n' >&2
  exit 1
fi

"${base[@]}" up -d --wait
"${apps[@]}" up -d
