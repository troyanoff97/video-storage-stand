# Enhanced disk-fault simulation (локальный stand)

Локальная **enhanced simulation** отказов диска/mount для SeaweedFS на loopback ext4.  
**Не заменяет** production bare-metal sign-off и **не** является customer acceptance.

**Скрипты:** `scripts/disk-sim/`  
**Связанные документы:** [SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md](SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md), [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md) §8, [seaweedfs-disk-health.md](seaweedfs-disk-health.md)

---

## 1. Цель

Заказчик **не предоставляет** isolated bare-metal / staging volume node.  
Нужно локально проверить поведение **per-dir** fault scenarios ближе к production (`/mnt/stor1`…`/mnt/stor14`), чем Docker tmpfs chaos:

- disk full (ENOSPC);
- read-only remount;
- mount unavailable (umount);
- recovery;
- сбор диагностик stand + host mounts.

---

## 2. Почему Docker chaos недостаточен

| Ограничение stand chaos | Эффект |
|-------------------------|--------|
| tmpfs / overlay в контейнере | `remount ro`, `fallocate`, umount — **WARN/SKIP** |
| Мало реальных mount points | Не моделирует 14 `-dir` на node |
| Нет block-level I/O errors | dm-error / partial hang не воспроизводятся |

`make chaos-matrix` / `chaos-multi-dir` доказывают **client path**; enhanced simulation — **host FS semantics** на controlled ext4.

---

## 3. Что проверяет enhanced simulation

| Сценарий | Скрипт | Проверка |
|----------|--------|----------|
| Baseline mounts | `setup_loopback_dirs.sh` | 2× ext4 loopback, `findmnt`/`df` |
| Disk full | `test_disk_full.sh` | ENOSPC, write probe fails |
| Read-only | `test_readonly_mount.sh` | `remount,ro`, write probe fails |
| Mount down | `test_mount_unavailable.sh` | `umount`, path unavailable |
| Recovery | `recover_mounts.sh` | remount rw, writable again |
| Logs | `collect_logs.sh` | docker logs, curl health/metrics/assign |
| Optional I/O error | `test_dm_error.sh` | документирует dm-error; auto-run **нет** |

**Интеграция с weed volume:** скрипты работают на **host** mount points. Полный E2E с `weed volume -dir=...` требует bind-mount sim dirs в compose (опционально, вне default flow). `collect_logs.sh` снимает состояние **работающего** stand.

---

## 4. Что не проверяет

- SMART, RAID, multipath, реальная latency disk hardware
- 14 production mount points на одном physical host
- Production `minFreeSpace=50GiB` на реальных TB-дисках
- Полный sign-off ТЗ §4.2–4.5 на metal
- Автоматический dm-error без ручной настройки

---

## 5. Safety model

| Правило | Реализация |
|---------|------------|
| Только controlled paths | `DISK_SIM_ROOT=/tmp/seaweedfs-disk-sim` |
| **Не** трогать `/mnt/stor*` | `safe_path` guard в `common.sh` |
| Destructive ops | `CONFIRM_DISK_SIM=1` обязателен |
| Cleanup | только `/tmp/seaweedfs-disk-sim`; отказ если path иной |
| Docker volumes | **не** `docker compose down -v` |
| sudo | mount/umount/losetup — через `sudo` при необходимости |

---

## 6. Требования

- Linux, `losetup`, `mkfs.ext4`, `mount`, `umount`, `df`, `findmnt`, `dd`
- Права sudo для mount (или root)
- Для `collect_logs.sh`: stand поднят (`make up && make health`)
- ~1 GiB свободного места в `/tmp` (2× 512 MiB images по умолчанию)

Переменные:

| Переменная | Default | Описание |
|------------|---------|----------|
| `DISK_SIM_ROOT` | `/tmp/seaweedfs-disk-sim` | Корень simulation |
| `DISK_SIM_SIZE_MB` | `512` | Размер каждого loop image |
| `CONFIRM_DISK_SIM` | — | `1` для destructive scripts |

---

## 7. Сценарии

### Baseline

```bash
CONFIRM_DISK_SIM=1 ./scripts/disk-sim/setup_loopback_dirs.sh
./scripts/disk-sim/collect_logs.sh
```

### Disk full

```bash
CONFIRM_DISK_SIM=1 ./scripts/disk-sim/test_disk_full.sh      # default: stor1
CONFIRM_DISK_SIM=1 ./scripts/disk-sim/recover_mounts.sh
```

### Read-only mount

```bash
CONFIRM_DISK_SIM=1 ./scripts/disk-sim/test_readonly_mount.sh
CONFIRM_DISK_SIM=1 ./scripts/disk-sim/recover_mounts.sh
```

### Mount unavailable

```bash
CONFIRM_DISK_SIM=1 ./scripts/disk-sim/test_mount_unavailable.sh
CONFIRM_DISK_SIM=1 ./scripts/disk-sim/recover_mounts.sh
```

### Log collection

```bash
./scripts/disk-sim/collect_logs.sh
# → /tmp/seaweedfs-disk-sim/logs/<timestamp>/
```

### Optional dm-error

```bash
CONFIRM_DISK_SIM=1 ./scripts/disk-sim/test_dm_error.sh
```

Только справка; ручной dmsetup на disposable VM.

### Cleanup

```bash
CONFIRM_DISK_SIM=1 ./scripts/disk-sim/cleanup_loopback_dirs.sh
```

### Makefile

```bash
make disk-sim-setup
make disk-sim-logs
make disk-sim-full
make disk-sim-readonly
make disk-sim-mount-down
make disk-sim-recover
make disk-sim-cleanup
```

---

## 8. Как интерпретировать результаты

| Host sim result | Значение для SeaweedFS |
|-----------------|----------------------|
| ENOSPC на одном mnt | Аналог одного `-dir` full; ожидаем skip dir + writes на healthy dirs |
| remount,ro | Аналог readonly volume location |
| umount | Аналог missing mount / cable pull на одном path |
| recover + writable | Аналог remount / disk restore |

**PASS** host sim: probe write fails/restores as expected.  
**Для stand:** после fault (если bind-mount в volume) — `curl :8880/v1/write-health`, `make test-sideweed`, логи volume/master из `collect_logs.sh`.

---

## 9. Что отправлять заказчику

- Этот doc + [SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md](SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md) (без secrets)
- Результаты host sim (df/findmnt screenshots, без internal paths с credentials)
- Архив `collect_logs.sh` (redacted) при инциденте
- Явная оговорка: **local simulation ≠ production sign-off**

---

## 10. Что просить при real disk incident

**Customer-side safe mode** (без destructive tests на production):

1. `weed volume` / master logs за окно инцидента
2. `df -h`, `findmnt`, `dmesg` на affected node
3. `curl master:9333/cluster/status`, volume `/status`
4. Список unhealthy dirs / volume IDs из логов
5. **Не** запускать `fallocate`/remount ro на production без isolated node

Destructive reproduction — **только** на isolated test host или через наш local sim.

---

## 11. Ограничения

- Заказчик не предоставляет bare-metal/staging → local sim **снижает риск**, не закрывает ТЗ §4 полностью
- Production 14×`-dir` — sim использует **2** loopback dirs
- Bind-mount sim → docker volume — optional; default scripts host-only
- dm-error — manual only
- Push/sign-off — отдельное решение заказчика

---

*Enhanced simulation добавлена в stand repo для локальной проверки. Physical disk sign-off — pending customer isolated node or incident log review.*
