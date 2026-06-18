# Инструменты только для debug (не production)

Production-клиенты **никогда** не обращаются к volume nodes или `master /dir/assign` напрямую.

Сборка стенда SeaweedFS всё равно требует pinned fork — см. [SEAWEEDFS_PIN.md](SEAWEEDFS_PIN.md) (`make check-seaweedfs`).

## Скрипты

| Скрипт | Что делает |
|--------|------------|
| `scripts/debug/put_fragment_direct.sh` | `master /dir/assign` → прямой POST на volume |
| `scripts/debug/put_to_volume1.sh` | То же, привязка к volume1 (`replication=000`, `dc1`) |
| `scripts/debug/master_assign.sh` | curl `GET /dir/assign` (внутренний API master) |
| `scripts/debug/volume_url.sh` | Маппинг `volumeN:8080` → localhost для direct PUT |

Обёртки в корне репозитория редиректят в `scripts/debug/`:

- `scripts/put_fragment_direct.sh`
- `scripts/put_to_volume1.sh`

## Docker compose profile `debug`

```bash
docker compose --profile debug up -d sideweed-volumes
```

`sideweed-volumes:8884` → `volume1:8080`, `volume2:8080` (только native fid GET).

## Флаг debug в Go-клиенте

```bash
USE_DIRECT_VOLUME_PUT=1 ./bin/fragment put file.bin camera-1
# или
./bin/fragment put --direct-volume file.bin camera-1
```

## Интеграционные тесты (debug)

```bash
RUN_DEBUG_INTEGRATION=1 go test -tags='integration debug' -v ./test/integration/ -run TestDebugAssignToVolume1
```

## Production paths (для сравнения)

| Операция | Path |
|----------|------|
| PUT | `scripts/put_fragment.sh` → sideweed → S3 |
| Snapshot PUT | `scripts/put_snapshot.sh` → bucket `csb` |
| GET | `scripts/get_fragment.sh` → HAProxy → S3 |

См. [README-STAND.md](../README-STAND.md).
