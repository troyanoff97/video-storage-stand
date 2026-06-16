# SeaweedFS weed-volume: per-disk health isolation

Fork: **https://github.com/troyanoff97/seaweedfs** (ветка `feat/volume-disk-health-isolation`, локально `./seaweedfs`).

Стенд собирает образ из форка: `docker/seaweedfs.Dockerfile` → `make up` (не upstream `chrislusf/seaweedfs`).

> Push в remote не выполняется автоматически — только локальные коммиты.

## Логика

```
                    ┌─────────────────┐
  PUT / assign ───► │  Store          │
                    │ FindFreeLocation│──► skip unhealthy + diskSpaceLow
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
         DiskLocation   DiskLocation   DiskLocation
         healthy        UNHEALTHY      healthy
         /data1         /data2         /data3
```

| Состояние | Поведение |
|-----------|-----------|
| **healthy** | Новые volumes, assign growth, записи |
| **unhealthy** | Исключён из `FindFreeLocation`; существующие volumes остаются для read |
| **isDiskSpaceLow** | Как раньше — readonly volumes + skip в FindFreeLocation |

**Переход в unhealthy:**
- I/O error при write/read/delete (`IsDiskError`)
- `-dir` недоступен при старте (multi-dir: warn, не FATAL)
- Ошибка роста volume на диске

**Recovery (каждую минуту):**
- `util.TestFolderWritable(dir)` → если OK, лог `recovered and is healthy again`

## Логи

```
E ... disk location /data2 marked unhealthy (io): read-only file system; new writes disabled on this directory
I ... disk location /data2 recovered and is healthy again; writes re-enabled
E ... disk location /data1 not writable at startup: Not writable! 
```

## Изменённые файлы

| Файл | Функции |
|------|---------|
| `weed/storage/disk_health.go` | **NEW** `IsDiskError` |
| `weed/storage/disk_location_health.go` | **NEW** `IsHealthyForWrites`, `ReportDiskError`, `markUnhealthy`, `tryRecoverHealth` |
| `weed/storage/disk_location.go` | health fields; `checkHealthAndDiskSpace`; I/O on load |
| `weed/storage/store.go` | `NewStore` startup check; `FindFreeLocation` skip unhealthy |
| `weed/storage/volume_write.go` | `checkReadWriteError` → `ReportDiskError` |
| `weed/command/volume.go` | multi-dir: не FATAL на одном bad `-dir` |

## Тесты

```bash
cd seaweedfs/weed
go test ./storage/... -run 'TestIsDiskError|TestDiskLocationHealth|TestFindFreeLocation|TestStartupUnhealthy' -v
```

## Интеграционный сценарий (локальный стенд)

1. Собрать образ из форка:
   ```bash
   cd seaweedfs/docker
   docker build -t seaweedfs-disk-health:local -f Dockerfile.local ../..
   ```

2. Два `-dir` на volume node:
   ```bash
   weed volume -dir=/data1,/data2 -max=3,3 -mserver=master:9333
   ```

3. **Write error / disk full** — заполнить только `/data1`:
   ```bash
   docker compose exec volume1 sh -c 'fallocate -l 500M /data1/fill'
   ./scripts/put_to_volume1.sh /tmp/test.bin chaos-write
   # assign должен уйти на /data2; в логах — unhealthy для /data1 при ENOSPC
   ```

4. **Read-only** — `mount -t tmpfs -o remount,ro tmpfs /data1` (см. `make chaos-volume1`)

5. **Mount unavailable** — `chmod 000 /data1` + restart не нужен: startup пометит unhealthy

6. **Recovery** — `reset_volumes.sh` / remount rw → через 1 мин или `tryRecoverHealth` в логах

## Ограничения

- Один `-dir` + он unhealthy → process всё ещё FATAL при старте (нет fallback)
- Read с unhealthy диска возвращает ошибку клиенту (не скрывается)
- `lastIoError` на volume по-прежнему может удалить volume на heartbeat (upstream behaviour)
