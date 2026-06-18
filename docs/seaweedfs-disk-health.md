# SeaweedFS weed-volume: per-disk health isolation

Патчи в локальном clone `./seaweedfs` (ветка `feat/volume-disk-health-isolation`), база — upstream [seaweedfs/seaweedfs](https://github.com/seaweedfs/seaweedfs) tag 3.80.

**GitHub-fork для SeaweedFS:** отдельного репозитория нет. **sideweed fork:** [github.com/troyanoff97/sideweed](https://github.com/troyanoff97/sideweed).

Стенд: `docker/seaweedfs.Dockerfile` → `make up` (не `chrislusf/seaweedfs`).

> Push не выполняется агентом.

## Логика

```
                    ┌─────────────────┐
  PUT / assign ───► │  Master         │
                    │ VolumeLayout    │──► skip ReadOnly volume IDs
                    └────────▲────────┘
                             │ heartbeat (ReadOnly per volume)
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
         DiskLocation   DiskLocation   DiskLocation
         healthy        UNHEALTHY      healthy
         /data1         /data2         /data3
              │              │
         vol 1 writable  vol 2 readonly (existing)
              │              │
              └─ FindFreeLocation skips unhealthy (new volumes)
```

| Состояние | Поведение |
|-----------|-----------|
| **healthy** | Новые volumes, assign, записи |
| **unhealthy** | Все **existing** volumes на dir → `IsReadOnly()`; master исключает их из `writables`; `FindFreeLocation` skip |
| **isDiskSpaceLow** | Как раньше — через `IsHealthyForWrites()` → readonly + skip |

### Цепочка volume node → master

1. `DiskLocation.markUnhealthy` / recovery → volumes на dir становятся readonly (`Volume.IsReadOnly()` ← `!location.IsHealthyForWrites()`).
2. `Store.CollectHeartbeat()` → `VolumeInformationMessage.ReadOnly=true` для affected volumes.
3. Немедленный heartbeat при смене health (`DiskHealthChangeChan`).
4. Master `SyncDataNodeRegistration` → `EnsureCorrectWritables` → volume ID убирается из `VolumeLayout.writables`.
5. `PickForWrite` / `/dir/assign` больше не возвращает volume ID на сломанном dir.

**Переход в unhealthy:**
- I/O error при write/read/delete (`IsDiskError`, incl. permission denied)
- `-dir` недоступен при старте (FATAL только если **все** `-dir` недоступны)
- Ошибка роста volume на диске (`addVolume` → `ReportDiskError`)

**Recovery (каждую минуту + при успешном `TestFolderWritable`):**
- volumes на dir снова writable; master получает heartbeat и возвращает volume ID в `writables`

## Логи

```
E ... disk location /data1 marked unhealthy (io): read-only file system; new writes disabled on this directory; existing volumes marked readonly: 3, 7
I ... volume server 127.0.0.1:8080 disk health changed, sending heartbeat
I ... disk location /data1 recovered and is healthy again; volumes restored to writable: 3, 7
```

Master (upstream):

```
I ... volume 3 are not all writable
I ... volume 3 remove from writable
```

## /status (volume node)

`GET /status` → `DiskHealth[]`:

```json
{
  "Directory": "/data1",
  "Healthy": false,
  "HealthyForWrites": false,
  "DiskSpaceLow": false,
  "LastError": "input/output error",
  "UnhealthySince": "2026-06-17T12:00:00Z",
  "ReadOnlyVolumeIds": [3, 7]
}
```

**Prometheus:** `seaweed_volumeServer_disk_healthy{dir}`.

## Изменённые файлы (итерация 2)

| Файл | Изменение |
|------|-----------|
| `weed/storage/volume.go` | `IsReadOnly()` учитывает `!location.IsHealthyForWrites()` |
| `weed/storage/disk_location_health.go` | лог volume IDs; `ReadOnlyVolumeIds` в snapshot; notify master |
| `weed/storage/disk_location.go` | `onDiskHealthChange` callback |
| `weed/storage/store.go` | `DiskHealthChangeChan`; `/status` ReadOnlyVolumeIds |
| `weed/server/volume_grpc_client_to_master.go` | немедленный heartbeat при смене disk health |

## Тесты

```bash
cd seaweedfs/weed

# volume node: existing volumes readonly + heartbeat
go test ./storage -run 'TestIsDiskError|TestDiskLocationHealth|TestFindFreeLocation|TestStartupUnhealthy|TestAddVolumeReportsDiskError|TestUnhealthyDirMarksExistingVolumesReadOnly|TestHeartbeatReportsUnhealthyDirVolumesReadOnly' -v

# master: assign не возвращает volume ID на unhealthy dir
go test ./topology -run TestMasterAssignSkipsVolumesOnUnhealthyDiskDir -v
```

## Build (stand)

```bash
cd /home/cerf/Desktop/work2
make up
make chaos-multi-dir   # /data1 fault → PUT на /data2
```

Customer private fork: [seaweedfs-customer-fork.md](seaweedfs-customer-fork.md).  
Production (bare metal): [PRODUCTION-DEPLOY.md](PRODUCTION-DEPLOY.md).

## Ограничения

- Read с unhealthy диска возвращает ошибку клиенту (не скрывается)
- `lastIoError` на volume по-прежнему может удалить volume на heartbeat (upstream behaviour)
- Master узнаёт о readonly через heartbeat; задержка ≤ `pulseSeconds`, при смене health — сразу (extra heartbeat)
