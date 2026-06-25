# Локальный стенд: production-like SeaweedFS + sideweed + S3

## Архитектура (подтверждена заказчиком)

```
WRITE:
  client → sideweed:8880 → S3 Gateway:8333 → filer:8888 → master → volume nodes

READ:
  client → HAProxy:8882 → sideweed-read → S3 Gateway:8333
  (в production read может идти напрямую через sideweed)

Snapshots: тот же write path, bucket csb
```

**Правила production:**
- Клиенты **никогда** не обращаются к volume nodes напрямую
- sideweed балансирует **S3 Gateway**, а не volume nodes
- HAProxy/Varnish — только read path
- Прямой доступ к volume — **только debug** → [docs/DEBUG.md](docs/DEBUG.md)
- Write sideweed блокирует PUT при нездоровом write path SeaweedFS → [docs/sideweed-health.md](docs/sideweed-health.md)

## Быстрый старт

```bash
git clone git@github.com:troyanoff97/video-storage-stand.git
cd video-storage-stand
git submodule update --init --recursive
SEAWEEDFS_REPO_URL=git@github.com:troyanoff97/seaweedfs.git make init-seaweedfs
make check-seaweedfs
make up && make health && make test
./scripts/verify_production_path.sh
```

**Репозитории:** stand — [video-storage-stand](https://github.com/troyanoff97/video-storage-stand); SeaweedFS fork — [seaweedfs](https://github.com/troyanoff97/seaweedfs); sideweed fork — [sideweed](https://github.com/troyanoff97/sideweed). Go module: `github.com/troyanoff97/video-storage-stand` (совпадает с именем repo).

SeaweedFS — **внешний customer fork** (не submodule). Pin: [docs/SEAWEEDFS_PIN.md](docs/SEAWEEDFS_PIN.md).

## Порты

| Сервис | Порт | Роль |
|--------|------|------|
| sideweed | 8880 | production write |
| haproxy | 8882 | production read |
| s3 | 8333 | S3 Gateway |
| filer | 8888 | filer |
| master | 9333 | topology (internal) |
| volume1/2 | 8080/8081 | blobs (internal) |
| cassandra | 9042 | индекс фрагментов на стенде |

**Observability (write sideweed):** `GET :8880/v1/write-health`, `GET :8880/metrics` — см. [docs/SIDEWEED-ALERTING.md](docs/SIDEWEED-ALERTING.md).

## Команды

```bash
# Production PUT (фрагменты)
./scripts/put_fragment.sh /tmp/file.bin camera-1

# Production PUT (снимки → bucket csb)
./scripts/put_snapshot.sh /tmp/snap.bin snap-1

# Production GET (снимки → bucket csb)
./scripts/get_snapshot.sh snap-1 <fragment_uuid> /tmp/snap-out.bin

# Production GET (фрагменты архива)
./scripts/get_fragment.sh camera-1 <uuid>

# Список фрагментов по времени (metadata only)
./scripts/list_fragments.sh camera-1 2026-06-24T00:00:00Z 2026-06-24T23:59:59Z

# Только debug
./scripts/debug/put_fragment_direct.sh /tmp/file.bin camera-debug
```

## Makefile

| Target | Описание |
|--------|----------|
| `make test` | Smoke: production PUT + GET (archive) |
| `make test-snapshot` | Smoke: snapshot PUT + GET via bucket csb |
| `make test-range-query` | Smoke: Cassandra list by camera + time range |
| `make check-seaweedfs` | Проверка SeaweedFS fork на pin `1528e7d` |
| `make init-seaweedfs` | Клон customer fork (`SEAWEEDFS_REPO_URL`) |
| `make test-sideweed` | Write gate sideweed при деградации (30 сценариев) |
| `make chaos-multi-dir` | Disk health через S3 path |
| `make chaos-matrix` | Матрица отказов через S3 path |
| `make put-v1` | **Debug** — редирект на `scripts/debug/put_to_volume1.sh` |

## Документация

- [PRODUCTION-CONFIG-AUDIT.md](docs/PRODUCTION-CONFIG-AUDIT.md) — read-only audit production configs (archives stor1/teye)
- [SEAWEEDFS-ENHANCED-DISK-SIMULATION.md](docs/SEAWEEDFS-ENHANCED-DISK-SIMULATION.md) — host loopback disk-fault simulation (ручной прогон PASS 2026-06-25)
- [TZ-IMPLEMENTATION-STATUS.md](docs/TZ-IMPLEMENTATION-STATUS.md) — сводный статус по исходному ТЗ (internal)
- [CASSANDRA-TASK-STATUS.md](docs/CASSANDRA-TASK-STATUS.md) — статус Задачи №2 (Cassandra §5)
- [STAND-TESTING.md](docs/STAND-TESTING.md)
- [TZ-DEVIATIONS.md](docs/TZ-DEVIATIONS.md)
- [PRODUCTION-DEPLOY.md](docs/PRODUCTION-DEPLOY.md)
- [DEBUG.md](docs/DEBUG.md)
- [sideweed-health.md](docs/sideweed-health.md)
- [SIDEWEED-ALERTING.md](docs/SIDEWEED-ALERTING.md) — metrics + sample alert rules (`observability/`)
- [SEAWEEDFS_PIN.md](docs/SEAWEEDFS_PIN.md)
- [PUSH-CHECKLIST.md](docs/PUSH-CHECKLIST.md)
- [seaweedfs-disk-health.md](docs/seaweedfs-disk-health.md)
