#!/bin/sh
set -eu

config=/etc/gitlab-runner/config.toml

if [ ! -s "$config" ]; then
  token="$(cat /run/secrets/gitlab_runner_token)"
  if [ -z "$token" ]; then
    printf 'GitLab Runner authentication token is empty.\n' >&2
    exit 1
  fi

  gitlab-runner register \
    --non-interactive \
    --url "https://gitlab.${SERVER_NAME}/" \
    --tls-ca-file "/etc/gitlab-runner/certs/gitlab.${SERVER_NAME}.crt" \
    --token "$token" \
    --name "infra-docker-runner" \
    --executor docker \
    --docker-image docker:28.0.4-cli \
    --docker-network-mode infra \
    --docker-pull-policy if-not-present \
    --docker-volumes /var/run/docker.sock:/var/run/docker.sock \
    --docker-volumes "${RUNNER_CACHE_HOST_PATH}:/cache"
fi

exec gitlab-runner run --user=gitlab-runner --working-directory=/home/gitlab-runner
