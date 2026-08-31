#!/bin/sh
set -eu

mkdir -p \
  /data/grafana \
  /data/vault \
  /data/harbor \
  /data/harbor/registry \
  /data/harbor/job-logs \
  /data/harbor/ca-download \
  /data/harbor/trivy \
  /data/harbor/trivy/reports \
  /data/step-ca \
  /data/gitlab \
  /data/gitlab/config \
  /data/gitlab/config/trusted-certs \
  /data/gitlab/logs \
  /data/gitlab/data \
  /data/gitlab-runner \
  /data/gitlab-runner/config \
  /data/gitlab-runner/cache

chown 472:0 /data/grafana
chmod 0750 /data/grafana

chown 100:1000 /data/vault
chmod 0700 /data/vault

chown 10000:10000 \
  /data/harbor \
  /data/harbor/registry \
  /data/harbor/job-logs \
  /data/harbor/ca-download \
  /data/harbor/trivy \
  /data/harbor/trivy/reports
chmod 0750 \
  /data/harbor \
  /data/harbor/registry \
  /data/harbor/job-logs \
  /data/harbor/ca-download \
  /data/harbor/trivy \
  /data/harbor/trivy/reports

chown 0:0 /data/step-ca
chmod 0755 /data/step-ca
cp /etc/step-ca/root_ca.crt /data/step-ca/root_ca.crt
chown 0:0 /data/step-ca/root_ca.crt
chmod 0644 /data/step-ca/root_ca.crt

chown 0:0 /data/gitlab /data/gitlab/config /data/gitlab/logs /data/gitlab/data
chmod 0750 /data/gitlab /data/gitlab/config
# Puma runs as git and must traverse the data and logs bind-mount roots.
chmod 0755 /data/gitlab/logs /data/gitlab/data

chown 999:999 /data/gitlab-runner /data/gitlab-runner/config /data/gitlab-runner/cache
chmod 0750 /data/gitlab-runner /data/gitlab-runner/config /data/gitlab-runner/cache

# GitLab Omnibus updates certificate permissions during reconfigure, so its
# trusted-certs directory must be writable rather than a read-only bind mount.
cp /data/step-ca/root_ca.crt /data/gitlab/config/trusted-certs/root_ca.crt
chown 0:0 /data/gitlab/config/trusted-certs/root_ca.crt
chmod 0644 /data/gitlab/config/trusted-certs/root_ca.crt
