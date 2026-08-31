# Локальная инфраструктура

Проект разделен на два независимых Docker Compose-стека, использующих общую
сеть `infra` и общий каталог секретов.

## Структура

```text
base/
  docker-compose.yaml   Базовые сервисы и сеть infra
  check.sh              Проверка базового стека
  storage-init.sh       Подготовка базовых хранилищ
  traefik/              Edge router и step-ca trust
  postgres/
  clickhouse/
  redis/
  jaeger/
  otel/
  loki/
  alloy/
  prometheus/
  minio/

apps/
  docker-compose.yaml   Прикладные сервисы
  check.sh              Проверка прикладного стека
  storage-init.sh       Подготовка прикладных хранилищ
  base-ready.sh         Ожидание готовности base
  postgres-init.sh      Роли и базы прикладных сервисов
  postgres-create-app.sh Создание роли и базы для нового приложения
  vault/
  keycloak/
  gitlab/
  gitlab-runner/
  harbor/
  grafana/

secrets/                Общие file-based secrets
.env                    Локальная несекретная конфигурация
init-secrets.sh         Генерация секретов и rendered-конфигов
```

## Состав base

- Traefik
- PostgreSQL 17
- ClickHouse
- Redis Cluster из трех primary
- Redis Standalone для GitLab и Harbor
- Apache Kafka
- NATS
- Jaeger
- OpenTelemetry Collector
- Prometheus
- MinIO
- Loki
- Grafana Alloy

Base создает Docker-сеть `infra`. Вторая часть подключается к ней как к
external network, поэтому base необходимо запускать первым.

## Состав apps

- Vault
- Keycloak
- GitLab CE
- GitLab Runner (profile `ci`)
- Harbor с Trivy
- Grafana
- oauth2-proxy

`apps/postgres-init.sh` идемпотентно создает и обновляет роли и базы Grafana,
Keycloak, Harbor и GitLab. Base PostgreSQL не требует их секретов при первом
старте.

## PostgreSQL для нового приложения

После запуска base создайте отдельные роль и базу для приложения:

```bash
./apps/postgres-create-app.sh my_app
```

Скрипт идемпотентен: роль и база называются `my_app`, пароль хранится в
`secrets/my_app_db_password`. При повторном запуске роль и ее пароль
обновляются, существующая база сохраняется. В Compose подключите этот файл как
secret и используйте `postgres:5432`, базу `my_app` и пользователя `my_app`.

## Подготовка

Создайте локальную конфигурацию:

```bash
cp .env.example .env
```

Заполните как минимум:

```env
SERVER_NAME=home.example
DATA_ROOT=/srv/infra/data
LAN_BIND_IP=192.168.1.10
STEP_CA_HOST=ca.home.example
STEP_CA_EMAIL=infra@home.example
```

Скопируйте корневой сертификат step-ca:

```text
base/traefik/certs/root_ca.crt
```

`storage-init` копирует сертификат в `${DATA_ROOT}/step-ca` с mode `0644` для
сервисов, которые запускаются не от root.

Сгенерируйте секреты и конфиги с credentials:

```bash
./init-secrets.sh
```

Каталог `secrets/` имеет mode `0700`. Значения секретов не должны попадать в
`.env`, Compose labels или Git.

## Запуск

Запустите base и apps:

```bash
./start.sh
```

Скрипт запускает base, затем apps и после готовности GitLab применяет его
настройки безопасности. Если существует `secrets/gitlab_runner_token`, он также
запускает GitLab Runner. `base-ready` проверяет PostgreSQL, Redis Standalone,
Loki, Prometheus, Jaeger и Traefik до запуска сервисов apps.

## Остановка

```bash
./stop.sh
```

Не останавливайте base первым: он владеет общей сетью `infra` и предоставляет
PostgreSQL, Redis, telemetry и HTTPS routing для apps.

## Проверка

```bash
./base/check.sh
./apps/check.sh
```

Проверка apps предполагает, что Vault уже инициализирован и unsealed.

## Vault

Первичная инициализация:

```bash
docker compose --env-file .env -f apps/docker-compose.yaml exec vault vault operator init
```

После каждого запуска введите необходимое число unseal keys:

```bash
./apps/vault/unseal.sh
```

Скрипт запрашивает ключи по одному и не сохраняет их. Для ручного запуска
остается доступна команда `docker compose --env-file .env -f apps/docker-compose.yaml exec vault vault operator unseal`.

Настройка OIDC после init/unseal:

```bash
VAULT_TOKEN='...' ./apps/vault/configure-oidc.sh
```

Unseal keys и initial root token храните вне этого репозитория.

## GitLab Runner

Runner использует Docker executor, собирает образы через Docker socket и хранит
cache и конфигурацию под `${DATA_ROOT}/gitlab-runner`. Создайте project или group
runner в GitLab, отключите для него untagged jobs и назначьте tag `docker`.
Сохраните выданный authentication token (`glrt-...`) без попадания в shell history:

```bash
read -rs -p 'GitLab Runner token: ' token
printf '\n'
umask 077
printf '%s\n' "$token" > secrets/gitlab_runner_token
unset token
```

После готовности GitLab перезапустите общий скрипт:

```bash
./start.sh
```

При первом запуске runner автоматически регистрируется в GitLab. Docker daemon
на хосте runner должен доверять root certificate step-ca, чтобы CI мог публиковать
образы в `https://harbor.${SERVER_NAME}`.

## SSO

Keycloak автоматически импортирует realm и синхронизирует OIDC clients.
Подробная схема групп, callback URI и исключений для машинных протоколов
описана в [`docs/sso.md`](docs/sso.md).

## Сеть и адреса

Внутри `infra` сервисы доступны по Compose service names:

```text
postgres:5432
clickhouse:8123
redis-node-0:6379
redis-node-1:6379
redis-node-2:6379
redis-standalone:6379
kafka:9092
nats:4222
jaeger:16686
otel-collector:4317
otel-collector:4318
prometheus:9090
keycloak:8080
gitlab:80
harbor-core:8080
grafana:3000
```

На `LAN_BIND_IP` публикуются:

```text
80, 443              Traefik
2222                 GitLab SSH, настраивается GITLAB_SSH_PORT
4222                 NATS
5432                 PostgreSQL
9000                 ClickHouse Native
9092                 Kafka
```

Через Traefik доступны:

```text
https://clickhouse.${SERVER_NAME}
https://vault.${SERVER_NAME}
https://keycloak.${SERVER_NAME}
https://gitlab.${SERVER_NAME}
https://harbor.${SERVER_NAME}
https://grafana.${SERVER_NAME}
https://prometheus.${SERVER_NAME}
https://jaeger.${SERVER_NAME}
https://oauth.${SERVER_NAME}
https://otel-http.${SERVER_NAME}
otel-grpc.${SERVER_NAME}:443
```

Все DNS-имена должны разрешаться в `LAN_BIND_IP` как на LAN-клиентах, так и
внутри контейнеров, использующих внешний OIDC issuer.

## Данные

Все persistent data хранятся как bind mounts под `${DATA_ROOT}`. Named volumes,
статические Docker IP и custom IPAM не используются.

Loki хранит логи в bucket `loki` на MinIO. Срок хранения задается
`LOKI_RETENTION_PERIOD` и по умолчанию составляет 30 дней. MinIO не опубликован
в LAN: Grafana обращается к Loki по внутренней Docker-сети.

## Логи контейнеров

Grafana Alloy автоматически собирает stdout/stderr Docker-контейнеров проектов
`infra-base` и `infra-apps` и отправляет их в Loki. В Grafana используйте
datasource `Loki` и фильтруйте по labels `compose_project`, `service` и
`container`. Alloy не собирает собственные логи, чтобы исключить цикл записи.
