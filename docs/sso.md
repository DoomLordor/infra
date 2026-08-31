# SSO через Keycloak

Keycloak используется как единый провайдер идентификации для браузерного
доступа. Сервисы с поддержкой OIDC подключаются к Keycloak напрямую. Для
Prometheus используется `oauth2-proxy` через Traefik ForwardAuth. Jaeger
доступен без SSO.

## Предварительные условия

Следующие имена должны разрешаться в `LAN_BIND_IP`:

```text
keycloak.${SERVER_NAME}
gitlab.${SERVER_NAME}
grafana.${SERVER_NAME}
harbor.${SERVER_NAME}
vault.${SERVER_NAME}
oauth.${SERVER_NAME}
jaeger.${SERVER_NAME}
prometheus.${SERVER_NAME}
```

До запуска стека поместите корневой сертификат внешнего step-ca в файл:

```text
base/traefik/certs/root_ca.crt
```

Создайте `.env` и сгенерируйте секреты:

```bash
cp .env.example .env
./init-secrets.sh
```

Скрипт создаст OIDC-секреты клиентов и ключ cookie для `oauth2-proxy` в
каталоге `secrets/`.

## Начальная настройка

При первом запуске Keycloak импортирует realm `${KEYCLOAK_REALM}` из
`apps/keycloak/realm.json`. Одноразовый сервис `keycloak-bootstrap` затем
синхронизирует группы, mapper claim `groups`, redirect URI и секреты клиентов.

Первый запуск выполняется через временного администратора Keycloak. Затем
создается service account `infra-bootstrap` с ролью `realm-admin` только внутри
`${KEYCLOAK_REALM}`. Последующие запуски используют этот service account.
После успешного запуска `apps/docker-compose.yaml` временного администратора в realm
`master` можно заменить постоянным.

Bootstrap управляет следующими confidential clients:

| Клиент | Redirect URI |
| --- | --- |
| `gitlab` | `https://gitlab.${SERVER_NAME}/users/auth/openid_connect/callback` |
| `grafana` | `https://grafana.${SERVER_NAME}/login/generic_oauth` |
| `harbor` | `https://harbor.${SERVER_NAME}/c/oidc/callback` |
| `vault` | `https://vault.${SERVER_NAME}/ui/vault/auth/oidc/oidc/callback` |
| `infra-forward-auth` | `https://oauth.${SERVER_NAME}/oauth2/callback` |

Не изменяйте секреты этих клиентов вручную в Keycloak. Повторный bootstrap
восстановит значения из каталога `secrets/`.

## Группы

Создайте пользователей в `${KEYCLOAK_REALM}` и назначьте им нужные группы:

| Группа | Доступ |
| --- | --- |
| `/grafana-viewers` | Роль Viewer в Grafana |
| `/grafana-editors` | Роль Editor в Grafana |
| `/grafana-admins` | Роль Admin в организации Grafana |
| `/harbor-users` | Группа для назначения проектных ролей Harbor |
| `/harbor-admins` | Системный администратор Harbor |
| `/vault-users` | Вход в Vault с политикой `default` |
| `/vault-admins` | Вход в Vault с политикой `vault-admin` |
| `/observability` | Доступ к Prometheus |

GitLab CE принимает пользователей из realm и создает учетную запись при
первом входе. GitLab CE не умеет назначать административные и проектные роли
по OIDC claim, поэтому эти роли управляются в самом GitLab.

## Поведение сервисов

- GitLab показывает вход через Keycloak и сохраняет локальный доступ `root`.
- Grafana автоматически перенаправляет пользователя в Keycloak. Для аварийного
  входа локальным администратором используйте `/login?disableAutoLogin=true`.
- Harbor использует native OIDC и автоматически создает учетные записи. Войти
  может любой пользователь realm; `/harbor-users` используется для проектных
  ролей, а не для ограничения входа. Создавать проекты могут только
  администраторы Harbor. Локальный `admin` остается аварийной учетной записью.
- Docker и Helm используют CLI secret из профиля пользователя Harbor после
  первого входа через браузер.
- Jaeger доступен без SSO.
- Prometheus доступен только участникам `/observability`.
- Vault сохраняет вход по токенам. OIDC включается отдельно после init/unseal.

Harbor можно переключить с database authentication на OIDC, только если в нем
нет локальных пользователей, кроме `admin`. Автоматическая настройка рассчитана
на новую базу Harbor.

## Vault

После инициализации и unseal настройте OIDC с помощью авторизованного токена,
не сохраняя его в репозитории:

```bash
VAULT_TOKEN='...' ./apps/vault/configure-oidc.sh
```

Команда включает `auth/oidc`, настраивает callback для UI и CLI, создает
политику `vault-admin` и связывает ее с группой `/vault-admins`. Команду можно
запускать повторно. Callback для CLI:
`http://localhost:8250/oidc/callback`.

## Машинные подключения

Браузерные перенаправления намеренно не применяются к машинным протоколам:

- GitLab SSH, API tokens и Git-over-HTTP
- Harbor `/v2/`, robot accounts и CLI secrets
- Vault API tokens
- OTLP HTTP/gRPC
- PostgreSQL, ClickHouse Native, Kafka, Redis и NATS
- внутренние scrape-запросы Prometheus и datasources Grafana

Self-managed ClickHouse не поддерживает браузерный OIDC. Его HTTP и Native
endpoints продолжают использовать учетные данные ClickHouse. Для работы людей
с запросами используется Grafana с SSO.

## Проверка

После установки настоящего CA и запуска стека выполните:

```bash
docker compose --env-file .env -f base/docker-compose.yaml ps
docker compose --env-file .env -f apps/docker-compose.yaml ps
./base/check.sh
./apps/check.sh
```

Jaeger должен отвечать без перенаправления в Keycloak. Неавторизованный запрос
к Prometheus должен пройти через `oauth.${SERVER_NAME}` и перенаправиться в
Keycloak. Пользователь без группы `/observability` не получает доступ к
Prometheus.
