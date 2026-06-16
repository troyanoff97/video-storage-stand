# SeaweedFS weed-volume: per-disk health isolation

Патчи в локальном clone `./seaweedfs` (ветка `feat/volume-disk-health-isolation`), база — upstream [seaweedfs/seaweedfs](https://github.com/seaweedfs/seaweedfs) tag 3.80.

**GitHub-fork для SeaweedFS:** отдельного репозитория нет. **sideweed fork:** [github.com/troyanoff97/sideweed](https://github.com/troyanoff97/sideweed).

Стенд: `docker/seaweedfs.Dockerfile` → `make up` (не `chrislusf/seaweedfs`).

> Push не выполняется агентом.

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
- I/O error при write/read/delete (`IsDiskError`, incl. permission denied)
- `-dir` недоступен при старте (single- or multi-dir: warn + unhealthy, FATAL только если **все** `-dir` недоступны)
- Ошибка роста volume на диске (`addVolume` → `ReportDiskError`)

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
| `weed/storage/store.go` | `NewStore` startup check; `FindFreeLocation` skip unhealthy; `addVolume` → `ReportDiskError` |
| `weed/storage/volume_write.go` | `checkReadWriteError` → `ReportDiskError` |
| `weed/command/volume.go` | single/multi-dir: FATAL only when **no** writable `-dir`; else start unhealthy |

## Тесты

```bash
cd seaweedfs/weed
go test ./storage/... -run 'TestIsDiskError|TestDiskLocationHealth|TestFindFreeLocation|TestStartupUnhealthy|TestAddVolumeReportsDiskError' -v
```

## Build (stand)

```bash
cd /home/cerf/Desktop/work2
make up   # docker/seaweedfs.Dockerfile builds from ./seaweedfs
```

## Интеграционный сценарий (локальный стенд)

**Multi-dir (recommended for patch demo):**

```bash
make chaos-multi-dir
# compose: docker-compose.yml + chaos + multi-dir
# volume1: -dir=/data1,/data2 -max=3,3
```

**Single-dir chaos** (`make chaos-volume1`) exercises disk full/ro but does not prove per-dir failover.

1. Два `-dir` на volume node (already in `docker-compose.multi-dir.yml`):

   ```bash
   weed volume -dir=/data1,/data2 -max=3,3 -mserver=master:9333
   ```

2. **Write error / disk full** — заполнить только `/data1`:

   ```bash
   ./scripts/chaos/disk_fail_data1.sh fill volume1
   ./scripts/put_to_volume1.sh /tmp/test.bin chaos-write
   ```

3. **Read-only** — `./scripts/chaos/disk_fail_data1.sh readonly volume1`

4. **Recovery** — `./scripts/chaos/reset_multi_dir_data1.sh volume1` → grep `recovered and is healthy again`

Customer private fork: [seaweedfs-customer-fork.md](seaweedfs-customer-fork.md).

## Ограничения

- Read с unhealthy диска возвращает ошибку клиенту (не скрывается)
- `lastIoError` на volume по-прежнему может удалить volume на heartbeat (upstream behaviour)
- Prometheus `/status` disk health export — not implemented (optional §4.4)
