# Локальный стенд: SeaweedFS + Cassandra + sideweed

Минимальный Docker Compose стенд для тестирования записи видеофрагментов через Native Volume API с sideweed как HTTP load balancer для **чтения**.

## Требования

- Docker + Docker Compose v2
- `curl`, `jq`, `python3`, `make`
- ~2 GB свободной RAM (Cassandra)

## Быстрый старт

```bash
cd /home/cerf/Desktop/work2

# sideweed — git submodule
git submodule update --init --recursive

make up
make health
make test
make test-go      # Go integration tests
make build-cli    # bin/fragment
```

## Go client

```bash
make build-cli
./bin/fragment put /tmp/test-fragment.bin camera-go
./bin/fragment get camera-go <fragment_uuid>

# Pin write to volume1 (replication 000 + dc1):
REPLICATION=000 ./bin/fragment put /tmp/test.bin camera-go --data-center dc1
# or:
make put-v1
```

Package: `pkg/fragment` — interface `Store`, implementation `Uploader`.

Resilience (Go client):

- **AssignWithRetry** — retries HTTP 406 / 5xx with exponential backoff
- **PutDirectWithRetry** — fresh assign + retry on PUT 5xx
- **GetViaSideweedWithRetry** — retries 502/503/504
- **Master circuit breaker** — opens after 3 connection failures (10s cooldown)

```bash
make test-unit    # resilience unit tests
make test-go      # integration (+ circuit breaker against live stack)
make chaos-volume1  # fault tests pinned to volume1 (stop volume2)
```

## Репозиторий и fork

- **Стенд (этот repo):** docker-compose, scripts, Go client, tests
- **sideweed submodule:** [github.com/troyanoff97/sideweed](https://github.com/troyanoff97/sideweed) (ваш fork)

```bash
git submodule sync
git submodule update --init --recursive
```

Dockerfile: `docker/sideweed.Dockerfile`, build context — submodule `./sideweed`.

## Pin assign на volume1 (chaos-тесты)

| Node | dataCenter | rack | replication для pin |
|------|------------|------|---------------------|
| volume1 | dc1 | rack1 | `000` + volume2 stopped |
| volume2 | dc1 | rack1 | `001` (replica в том же rack) |

Оба volume в **dc1/rack1** — иначе `replication=001` не создаёт writable volumes на fresh cluster.

```bash
./scripts/put_to_volume1.sh file.bin camera-1
make chaos-volume1
```

Подробнее: [docs/chaos-expectations.md](docs/chaos-expectations.md)

```bash
docker compose -f docker-compose.yml -f docker-compose.chaos.yml up -d --build
./scripts/wait-healthy.sh
```

## Архитектура

```
Client → master:9333        (/dir/assign)
Client → volumeN:808x       (PUT — напрямую на assigned volume)
Client → sideweed:8880      (GET — через LB)
         ├→ volume1:8080
         └→ volume2:8080
Client → cassandra:9042     (metadata)
```

**Write/read split:** PUT идёт **напрямую** на volume из assign (`volume1:8080` → `localhost:8080`, `volume2:8080` → `localhost:8081`). GET — **через sideweed** для тестирования failover.

| Сервис    | Host port | Назначение                          |
|-----------|-----------|-------------------------------------|
| master    | 9333      | assign, topology                    |
| volume1   | 8080      | primary volume node                 |
| volume2   | 8081      | replica node (replication `001`)    |
| sideweed  | 8880      | LB для GET                          |
| cassandra | 9042      | метаданные фрагментов               |

Prometheus metrics sideweed: `http://localhost:8880/.prometheus/metrics`

## Makefile

| Target | Описание |
|--------|----------|
| `make init` | `git submodule update --init` |
| `make up` | build + start stack |
| `make down` | stop stack |
| `make health` | wait for all services |
| `make test` | smoke test put + get (bash) |
| `make test-go` | Go integration tests |
| `make test-unit` | Go unit tests (resilience) |
| `make test-all` | bash + Go |
| `make build-cli` | `bin/fragment` |
| `make put-v1` | PUT на volume1 (dc1, replication 000) |
| `make chaos-matrix` | прогнать все fault-сценарии |
| `make chaos-volume1` | volume1-only faults (disk full/ro) |
| `make chaos-volume-down` | stop volume1 |
| `make chaos-master-down` | stop master |
| `make chaos-reset` | reset volume1 state |
| `make clean` | down + удалить volumes |

## Тестовые скрипты

| Скрипт | Описание |
|--------|----------|
| `scripts/wait-healthy.sh` | readiness + schema |
| `scripts/put_fragment.sh` | assign → **direct PUT** → Cassandra → verify GET via sideweed |
| `scripts/put_to_volume1.sh` | PUT pinned to volume1 (`dc1`, `replication=000`) |
| `scripts/get_fragment.sh` | SELECT + **GET via sideweed** |
| `scripts/chaos/run_matrix.sh` | автоматический прогон всех сценариев |

Переменные окружения: `MASTER_URL`, `SIDEWEED_URL`, `REPLICATION`.

## Chaos / fault injection

```bash
make chaos-matrix          # полный прогон, результат в chaos-matrix-results.txt
make chaos-volume-down     # или отдельные сценарии
make chaos-reset
```

## Результаты chaos-матрицы (2026-06-16, реальный прогон)

| # | Сценарий | Assign | PUT | GET (sideweed) | Ключевые логи |
|---|----------|--------|-----|----------------|---------------|
| 0 | baseline | HTTP 200 | HTTP 201, direct volume2 | HTTP 200 | — |
| 1 | volume1 down | **HTTP 406** | не дошло | **HTTP 200** (replica volume2) | sideweed: `"Status":"down"`, `"Err":"server misbehaving"` для volume1; master: `No writable volumes and no free volumes left` |
| 2 | mount unavailable (chmod 000 /data) | **HTTP 406** | не дошло | — | volume1: `FATAL Check Data Folder(-dir) Writable /data : Not writable!`; sideweed: volume1 DOWN |
| 3 | disk full (volume1) | HTTP 200 → volume2 | **exit 23** (write error на volume2 после fill) | — | fill ~48GB на volume1; assign ушёл на volume2 |
| 4 | disk read-only (volume1) | HTTP 200 → volume2 | HTTP 201 (volume2) | **HTTP 200** | remount ro на volume1; write обошёл через assign на volume2 |
| 5 | master down | **HTTP 000** (connection refused) | — | **HTTP 200** | volume1: `heartbeat to master:9333 error: rpc error: code = Unavailable desc = error reading from server: EOF` |

### Детали по HTTP-кодам

**Assign `/dir/assign`:**
- OK: `200` + `{"fid":"...","url":"volumeN:8080"}`
- Нет writable volumes: `406` + `"error":"failed to find writable volumes...No writable volumes and no free volumes left"`
- Master down: curl exit `7`, `HTTP_CODE:000`

**PUT (direct volume):**
- OK: `201` + `{"name":"...","size":...,"eTag":"..."}`
- Write error: exit `23` (curl write error) или HTTP `500`

**GET (via sideweed):**
- OK: `200`, blob size совпадает
- При replication `001` GET работает даже когда volume1 down (sideweed → volume2)

### Sideweed log patterns

```json
{"Type":"LOG","Endpoint":"http://volume1:8080","Status":"down","Error":{...,"Err":"server misbehaving"}}
{"type":"TRACE","host":"http://volume2:8080","statusCode":200,"method":"GET","path":"/4,08621f9973"}
```

### Volume log patterns

```
F0616 volume.go:159 Check Data Folder(-dir) Writable /data : Not writable!
I0616 volume_grpc_client_to_master.go:71 heartbeat to master:9333 error: rpc error: code = Unavailable desc = error reading from server: EOF
```

## Наблюдения

| Сценарий | Master | Sideweed | Client PUT | Client GET | Cassandra |
|----------|--------|----------|------------|------------|-----------|
| volume down | assign 406 | volume1 DOWN | fail (no assign) | OK via volume2 | no new row |
| mount gone | assign 406 | volume1 DOWN | fail | — | no new row |
| disk full | assign 200 | — | fail (curl 23) | — | no new row |
| disk ro | assign 200 (volume2) | volume1 UP | OK on volume2 | OK | new row |
| master down | down | unaffected | fail (assign) | OK | unaffected |

**Важно:** `/healthz` не отражает disk full/ro — sideweed помечает backend DOWN только при DNS/connection error или после failed proxy.

## Точки интеграции

1. **Write path** — PUT на direct URL из assign (`resolve_volume_url`).
2. **Read path** — GET через sideweed `:8880`.
3. **Assign** — обрабатывать HTTP 406 (no writable volumes) и connection refused (master down).
4. **Metadata** — INSERT в Cassandra только после успешного PUT.

## Остановка

```bash
make down
make clean   # + удалить volumes
```

## Submodule

```bash
git submodule update --init --recursive
# обновление sideweed:
cd sideweed && git pull origin master && cd ..
```

Dockerfile для сборки: [`docker/sideweed.Dockerfile`](docker/sideweed.Dockerfile) (build context: `./sideweed` submodule).
