# Локальный стенд: SeaweedFS + Cassandra + sideweed

Минимальный Docker Compose стенд для тестирования записи видеофрагментов через Native Volume API (`/dir/assign` → PUT/GET) с sideweed как HTTP load balancer перед volume nodes.

## Требования

- Docker + Docker Compose v2
- `curl`, `jq`, `python3`
- ~2 GB свободной RAM (Cassandra)

## Быстрый старт

```bash
cd /home/cerf/Desktop/work2

# sideweed уже в ./sideweed (git clone)
docker compose -f docker-compose.yml -f docker-compose.chaos.yml up -d --build
./scripts/wait-healthy.sh

# Health checks
curl -sf http://localhost:9333/cluster/status | jq .
curl -sf http://localhost:8080/healthz
curl -sf http://localhost:8081/healthz
curl -sf http://localhost:8880/v1/health
docker compose exec cassandra cqlsh -e "DESCRIBE KEYSPACES"

# Smoke test
dd if=/dev/urandom of=/tmp/test-fragment.bin bs=1M count=1 status=none
./scripts/put_fragment.sh /tmp/test-fragment.bin camera-1
# fragment_id печатается в выводе SUCCESS
./scripts/get_fragment.sh camera-1 <fragment_id>
```

## Архитектура

```
Client → master:9333 (/dir/assign)
Client → sideweed:8880 (PUT/GET /{fid})
         ├→ volume1:8080
         └→ volume2:8080
Client → cassandra:9042 (metadata)
```

| Сервис    | Host port | Назначение                          |
|-----------|-----------|-------------------------------------|
| master    | 9333      | assign, topology                    |
| volume1   | 8080      | primary volume node                 |
| volume2   | 8081      | replica node (replication `001`)    |
| sideweed  | 8880      | LB перед volume nodes               |
| cassandra | 9042      | метаданные фрагментов               |

Prometheus metrics sideweed: `http://localhost:8880/.prometheus/metrics`

## Проверка топологии SeaweedFS

```bash
curl -s http://localhost:9333/dir/status | jq .
curl -s http://localhost:9333/vol/status | jq .
docker compose logs sideweed --tail=20
```

## Тестовые скрипты

| Скрипт | Описание |
|--------|----------|
| `scripts/wait-healthy.sh` | Ждёт readiness всех сервисов, применяет schema |
| `scripts/put_fragment.sh <file> <camera_id> [fragment_id]` | assign → PUT via sideweed → Cassandra INSERT → verify GET |
| `scripts/get_fragment.sh <camera_id> <fragment_id> [out]` | SELECT из Cassandra + GET blob |

Переменные окружения (опционально): `MASTER_URL`, `SIDEWEED_URL`, `REPLICATION`.

## Chaos / fault injection

Используйте compose с chaos override (даёт `SYS_ADMIN` volume nodes):

```bash
docker compose -f docker-compose.yml -f docker-compose.chaos.yml ...
```

| Скрипт | Симуляция | Recovery |
|--------|-----------|----------|
| `scripts/chaos/volume_down.sh [volume1\|volume2]` | Остановка volume node | `volume_up.sh` |
| `scripts/chaos/master_down.sh` | Master недоступен | `master_up.sh` |
| `scripts/chaos/mount_unavailable.sh [volume1]` | `chmod 000 /data` | `reset_volumes.sh` |
| `scripts/chaos/disk_full.sh [volume1]` | Заполнение диска | `reset_volumes.sh` |
| `scripts/chaos/disk_readonly.sh [volume1]` | remount ro `/data` | `reset_volumes.sh` |
| `scripts/chaos/reset_volumes.sh [volume1]` | Сброс состояния volume | — |

### Пример сценария: volume down

```bash
./scripts/put_fragment.sh /tmp/test-fragment.bin camera-1   # baseline OK
docker compose stop volume1
sleep 5
./scripts/put_fragment.sh /tmp/test-fragment.bin camera-1   # PUT may fail
docker compose logs sideweed --tail=30
docker compose start volume1
```

## Наблюдения: что ломается и где смотреть

| Сценарий | Master | Sideweed | Volume logs | Client symptom | Cassandra |
|----------|--------|----------|-------------|----------------|-----------|
| volume down | topology update | backend DOWN, 502 if all down | heartbeat stop | PUT fail / GET maybe OK | INSERT only if PUT ok |
| mount gone | volume errors | proxy 5xx → DOWN | permission denied | PUT fail | no new rows |
| disk full | low space flag | proxy 5xx | ENOSPC | PUT fail | no new rows |
| disk ro | — | may stay UP | read-only fs | PUT fail, GET ok | no new rows |
| master down | down | unaffected | heartbeat errors | assign fail | unaffected |

### Где смотреть логи

```bash
docker compose logs master --tail=50
docker compose logs volume1 --tail=50
docker compose logs volume2 --tail=50
docker compose logs sideweed --tail=50
docker compose logs cassandra --tail=50
```

**Sideweed:** JSON-логи UP/DOWN transitions (`-l --json`), метрики `sideweed_errors_total`.

**Volume:** ошибки записи (`permission denied`, `read-only file system`, `no space left on device`), heartbeat errors при падении master.

**Важно:** `/healthz` volume server не отражает disk full/ro — sideweed узнаёт о проблеме через failed PUT (ErrorHandler).

## Точки интеграции (для прикладного кода)

1. **Blob client** — после assign заменить host volume URL на `sideweed:8880`; retry при 502/500.
2. **Assign** — `GET master:9333/dir/assign?replication=001`; circuit breaker при недоступности master.
3. **Metadata** — write-after-successful-PUT в Cassandra; read = SELECT fid + GET через sideweed.
4. **Monitoring** — scrape `/.prometheus/metrics`, `/healthz` per volume, `/cluster/status` master.

## Остановка и очистка

```bash
docker compose -f docker-compose.yml -f docker-compose.chaos.yml down
docker compose -f docker-compose.yml -f docker-compose.chaos.yml down -v   # удалить volumes
```
