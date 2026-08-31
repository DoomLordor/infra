#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
base=(docker compose --env-file "$root_dir/.env" -f "$root_dir/base/docker-compose.yaml")
apps=(docker compose --env-file "$root_dir/.env" -f "$root_dir/apps/docker-compose.yaml")
ci_apps=(docker compose --profile ci --env-file "$root_dir/.env" -f "$root_dir/apps/docker-compose.yaml")

"${base[@]}" up -d --wait
"${apps[@]}" up -d

if [[ -s "$root_dir/secrets/gitlab_runner_token" ]]; then
  "${ci_apps[@]}" up -d gitlab-runner
else
  printf 'GitLab Runner is skipped until secrets/gitlab_runner_token is created.\n'
fi
