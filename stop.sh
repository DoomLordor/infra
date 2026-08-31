#!/usr/bin/env bash
set -Eeuo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
apps=(docker compose --profile ci --env-file "$root_dir/.env" -f "$root_dir/apps/docker-compose.yaml")
base=(docker compose --env-file "$root_dir/.env" -f "$root_dir/base/docker-compose.yaml")

"${apps[@]}" stop
"${base[@]}" stop
