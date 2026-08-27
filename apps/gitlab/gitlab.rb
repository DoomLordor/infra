read_secret = ->(name) { File.read("/run/secrets/#{name}").chomp }

server_name = ENV.fetch('SERVER_NAME')
gitlab_hostname = "gitlab.#{server_name}"
gitlab_url = "https://#{gitlab_hostname}"

external_url gitlab_url
letsencrypt['enable'] = false

gitlab_rails['nginx']['listen_port'] = 80
gitlab_rails['nginx']['listen_https'] = false
gitlab_rails['nginx']['proxy_set_headers'] = {
  'Host' => '$http_host_with_default',
  'X-Real-IP' => '$remote_addr',
  'X-Forwarded-For' => '$proxy_add_x_forwarded_for',
  'X-Forwarded-Host' => '$http_host_with_default',
  'X-Forwarded-Proto' => 'https',
  'X-Forwarded-Ssl' => 'on',
  'X-Forwarded-Port' => '443',
  'Upgrade' => '$http_upgrade',
  'Connection' => '$connection_upgrade'
}

gitlab_rails['allowed_hosts'] = [gitlab_hostname]
gitlab_rails['gitlab_shell_ssh_port'] = ENV.fetch('GITLAB_SSH_PORT').to_i
gitlab_rails['gitlab_signup_enabled'] = false

postgresql['enable'] = false
postgresql['version'] = 17
gitlab_rails['db_adapter'] = 'postgresql'
gitlab_rails['db_encoding'] = 'unicode'
gitlab_rails['db_host'] = 'postgres'
gitlab_rails['db_port'] = 5432
gitlab_rails['db_database'] = 'gitlabhq_production'
gitlab_rails['db_username'] = 'gitlab'
gitlab_rails['db_password'] = read_secret.call('gitlab_db_password')

redis['enable'] = false
gitlab_rails['redis_host'] = 'redis-standalone'
gitlab_rails['redis_port'] = 6379
gitlab_rails['redis_password'] = read_secret.call('redis_standalone_password')
gitlab_rails['redis_database'] = 10
gitlab_rails['redis_ssl'] = false

registry['enable'] = false
prometheus_monitoring['enable'] = false

# The container is limited to 8 GiB; automatic worker sizing creates 25 Puma
# processes on this 32-core host and exhausts that limit.
puma['worker_processes'] = 2

gitlab_rails['initial_root_password'] = read_secret.call('gitlab_root_password')
gitlab_rails['display_initial_root_password'] = false
gitlab_rails['store_initial_root_password'] = false

keycloak_issuer = "https://keycloak.#{server_name}/realms/#{ENV.fetch('KEYCLOAK_REALM')}"
gitlab_rails['omniauth_enabled'] = true
gitlab_rails['omniauth_allow_single_sign_on'] = ['openid_connect']
gitlab_rails['omniauth_block_auto_created_users'] = false
gitlab_rails['omniauth_sync_profile_from_provider'] = ['openid_connect']
gitlab_rails['omniauth_sync_profile_attributes'] = ['name', 'email']
gitlab_rails['omniauth_providers'] = [
  {
    name: 'openid_connect',
    label: 'Keycloak',
    args: {
      name: 'openid_connect',
      scope: ['openid', 'profile', 'email'],
      response_type: 'code',
      issuer: keycloak_issuer,
      discovery: true,
      client_auth_method: 'query',
      gitlab_username_claim: 'preferred_username',
      pkce: true,
      client_options: {
        identifier: 'gitlab',
        secret: read_secret.call('gitlab_oidc_client_secret'),
        redirect_uri: "#{gitlab_url}/users/auth/openid_connect/callback"
      }
    }
  }
]
