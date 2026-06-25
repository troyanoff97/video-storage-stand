# Локальный стенд: production-like SeaweedFS + sideweed + S3

## Архитектура

```
WRITE: client → sideweed:8880 → S3 Gateway:8333 → filer → master → volumes
READ:  client → HAProxy:8882 → sideweed-read → S3
```

Клиенты **не** обращаются к volume nodes. Прямой volume — только debug (`scripts/debug/`).

## Быстрый старт

```bash
git clone git@github.com:troyanoff97/video-storage-stand.git
cd video-storage-stand
git submodule update --init --recursive
SEAWEEDFS_REPO_URL=git@github.com:troyanoff97/seaweedfs.git make init-seaweedfs
make check-seaweedfs
make up && make health && make test
```

SeaweedFS — внешний customer fork (pin `1528e7d`). Подробности: [docs/02-ARCHITECTURE.md](docs/02-ARCHITECTURE.md).

## Порты

| Сервис | Порт |
|--------|------|
| sideweed (write) | 8880 |
| haproxy (read) | 8882 |
| s3 | 8333 |
| filer | 8888 |
| cassandra | 9042 |

Observability: `GET :8880/v1/write-health`, `GET :8880/metrics`.

## Основные команды

```bash
make test              # archive PUT/GET
make test-snapshot     # csb snapshots
make test-range-query  # Cassandra range
make test-sideweed     # write gate (35 сценариев)
make chaos-matrix      # fault matrix via S3
```

Production scripts: `put_fragment.sh`, `put_snapshot.sh`, `get_fragment.sh`, `get_snapshot.sh`.

## Документация

| Файл | Содержание |
|------|------------|
| [docs/01-TZ-STATUS.md](docs/01-TZ-STATUS.md) | Статус по ТЗ §4–§8 |
| [docs/02-ARCHITECTURE.md](docs/02-ARCHITECTURE.md) | Архитектура, forks, health model |
| [docs/03-TESTING.md](docs/03-TESTING.md) | Тесты, chaos, disk-sim |
| [docs/04-OPERATIONS.md](docs/04-OPERATIONS.md) | Metrics, vmalert, инциденты |
| [docs/05-PRODUCTION-RUNBOOKS.md](docs/05-PRODUCTION-RUNBOOKS.md) | Deploy, migration, push |
| [docs/06-DELIVERY-SUMMARY.md](docs/06-DELIVERY-SUMMARY.md) | Краткая сводка для заказчика |

Disk-sim scripts: [scripts/disk-sim/README.md](scripts/disk-sim/README.md).
