# Правила работы с Docker-инфраструктурой

Следуй этим правилам при любых изменениях конфигурации в этом проекте.

## Общие принципы

- Инфраструктура работает в локальной сети. Не добавляй избыточные security-механизмы без явной необходимости.
- Предпочитай простую, явную и Docker-native конфигурацию.
- Используй два независимых Compose-проекта: `base/docker-compose.yaml` и `apps/docker-compose.yaml`.
- Base запускай первым и останавливай последним; apps подключается к созданной base-сетью `infra`.
- Не используй `latest`; фиксируй конкретные версии образов.
- Используй официальные Docker images и их стандартное поведение. Не переопределяй дефолтные конфиги без необходимости.
- Не копируй дефолтные конфиги целиком; храни только изменяемые параметры.
- Не создавай YAML anchors/extensions (`x-*`) ради небольшого сокращения конфигурации.
- Не добавляй конфигурацию «на будущее». Добавляй параметр только тогда, когда он решает текущую задачу и стандартного поведения image недостаточно.

## Docker-сеть

- Используй одну Docker-сеть `infra`:

  ```yaml
  networks:
    infra:
      name: infra
      driver: bridge
  ```

- Не используй `internal`, `ipam`, статические IP и network aliases без явной необходимости.
- Другие Compose-проекты подключают `infra` как внешнюю сеть:

  ```yaml
  networks:
    infra:
      external: true
      name: infra
  ```

- Внутри Docker обращайся к сервисам по service name: `postgres`, `clickhouse`, `grafana`, `prometheus`, `otel-collector`, `redis-node-0` и т. д.
- Не используй `${SERVER_NAME}` для внутреннего Docker DNS.
- Не пропускай внутренний container-to-container traffic через Traefik без необходимости.

## Публикация сервисов и Traefik

- Добавляй `ports` только для доступа из LAN вне Docker.
- Публикуй host-порты только на обязательный `${LAN_BIND_IP}`, без fallback на `0.0.0.0`.
- Публикуй HTTP/gRPC-сервисы через Traefik.
- Используй Traefik через Docker provider и labels.
- Используй `--providers.docker.exposedbydefault=false`.
- Допустим прямой read-only mount `/var/run/docker.sock`.
- Не используй Traefik file provider для маршрутов Docker-сервисов.
- Не создавай `dynamic.yml`, template-конфиги и init-контейнеры для генерации Traefik routes.
- Размещай Traefik labels непосредственно у соответствующего сервиса.
- Для контейнера с несколькими HTTP/gRPC-портами создавай отдельные Traefik services и явно связывай их с routers.
- Для OTLP gRPC backend на `4317` используй `h2c`.
- TLS обслуживает Traefik; сертификаты получай через ACME от локального `step-ca`.
- Учитывай, что LAN DNS направляет `*.${SERVER_NAME}` на LAN IP Traefik.

## Хранилище и скрипты

- Все persistent volumes делай bind mounts через `${DATA_ROOT}`; не используй named volumes.
- Подготовку каталогов и permissions выполняй отдельными `base/storage-init.sh` и `apps/storage-init.sh`.
- Не размещай в `docker-compose.yaml` большие shell-команды; вызывай отдельные `.sh`-файлы.
- Не создавай helper/init-контейнер, если задачу проще решить shell-скриптом.

## Конфигурация и секреты

- Используй `.env` только для несекретной конфигурации: `SERVER_NAME`, `LAN_BIND_IP`, `DATA_ROOT`, URLs и т. п.
- Не храни пароли, токены, ключи и password hashes в `.env`.
- Храни credentials в отдельных файлах в `secrets/`; не коммить их в Git.
- Если image поддерживает `*_FILE`, используй secret file вместо environment variable.
- Не передавай credentials или их hashes через environment без необходимости.

## PostgreSQL

- Используй стандартный `pg_hba.conf`, создаваемый официальным image. Добавляй кастомный файл только при необходимости специальных ACL.
- Переопределяй только необходимые параметры PostgreSQL, например `listen_addresses` и `password_encryption`.
- Базовую инициализацию PostgreSQL выполняй через `docker-entrypoint-initdb.d`.
- Роли и базы сервисов apps синхронизируй идемпотентным `apps/postgres-init.sh`.

## ClickHouse

- Для ClickHouse credentials используй secret files; не храни `*_PASSWORD_SHA256` в `.env`.
- ClickHouse HTTP (`8123`) публикуй через Traefik.
- ClickHouse native (`9000`) можно публиковать на `${LAN_BIND_IP}`, если нужен LAN-доступ.

## Redis

- Используй Redis как трехузловой Redis Cluster: `redis-node-0`, `redis-node-1`, `redis-node-2`.
- Docker-клиенты Redis Cluster используют эти service names как seed nodes.
- Не создавай Redis FQDN aliases до появления необходимости доступа к Redis Cluster из LAN.
- Учитывай, что Redis Cluster из трех primary без replicas обеспечивает sharding, но не полноценный HA.
- Не публикуй Redis Cluster в LAN до отдельной настройки announce/topology-адресов.

## Мониторинг и телеметрия

- Указывай Prometheus scrape targets внутри Docker напрямую по service name, без Traefik.
- Docker-приложения отправляют OTLP напрямую на `otel-collector:4317` или `otel-collector:4318`. Traefik OTLP endpoints предназначены для LAN-клиентов.

## Readiness и зависимости

- Добавляй healthcheck только для реальной проверки readiness; предпочитай native health commands.
- Не используй `depends_on` как замену retry/reconnect-логике приложения.
