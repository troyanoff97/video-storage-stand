# План bare-metal disk fault tests для SeaweedFS (ТЗ §4.2–4.5)

Практический план проверки отказа диска и изоляции **на физическом хосте / отдельном volume node**.  
**Не письмо заказчику** — внутренний runbook для acceptance Задачи №1.

**Статус выполнения:** план готов; **прогон на metal не выполнен**. Заказчик **не предоставил** bare-metal стенд ([PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md) §8). Production: **14 `-dir`** на volume node — per-dir isolation **релевантен**.

**Связанные документы:**

- [seaweedfs-disk-health.md](seaweedfs-disk-health.md) — логика патча disk-health
- [chaos-expectations.md](chaos-expectations.md) — ожидания Docker chaos-matrix
- [STAND-TESTING.md](STAND-TESTING.md) — smoke / chaos targets на стенде
- [TZ-DEVIATIONS.md](TZ-DEVIATIONS.md) — отличия stand vs production
- [SEAWEEDFS_PIN.md](SEAWEEDFS_PIN.md) — pin commit `1528e7d`
- [PRODUCTION-DEPLOY.md](PRODUCTION-DEPLOY.md) — production layout

---

## 1. Назначение

### Зачем bare-metal test

Патч disk-health (`feat/volume-disk-health-isolation`, pin **`1528e7d`**) меняет поведение **weed volume** при реальных I/O ошибках, недоступном mount и заполнении диска. Docker stand с **tmpfs/bind mounts** частично симулирует отказы, но **не воспроизводит** полный спектр physical disk failure.

Bare-metal test подтверждает, что поведение на production volume node совпадает с design doc и unit-тестами в fork.

### Почему Docker / tmpfs недостаточен

| Ограничение stand | Эффект |
|-------------------|--------|
| tmpfs / overlay FS | `remount ro`, `fallocate`, `mount --bind` работают непредсказуемо → chaos-matrix **WARN/SKIP** |
| Нет реального block device | Нет latency spikes, SMART errors, partial I/O hang |
| Один хост, мало дисков | RAID / multipath сценарии не покрыты |
| `replication=000` на dev | Failover между nodes упрощён vs production RF |

См. [chaos-expectations.md](chaos-expectations.md): сценарии mount-unavailable, disk-full, disk-readonly часто **SKIP**.

### Пункты ТЗ, которые закрывает bare-metal plan

| ТЗ | Содержание | Роль bare-metal |
|----|------------|-----------------|
| **4.2** | Обработка отказа диска | Сценарии B–G: fault → unhealthy, readonly, stop assign |
| **4.3** | Изоляция повреждённого диска | F, J: writes только на healthy location; master skip |
| **4.4** | Логирование | Observability §6: disk path, volume IDs, heartbeat |
| **4.5** | Восстановление | H: remount / recovery → writable, master restore |

---

## 2. Предусловия

| # | Требование |
|---|------------|
| P1 | **Отдельный test host** или выделенный volume node — **не production** |
| P2 | SeaweedFS fork, branch `feat/volume-disk-health-isolation`, commit **`1528e7d`** |
| P2a | Production layout: **14 `-dir`** per volume node (`/mnt/stor1`…`/mnt/stor14`) — см. [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md) |
| P3 | Stand repo: `origin/main` @ **`45daa7b`** |
| P4 | Минимум **2 writable locations** на одном volume node (`-dir=/mnt/weed-a,/mnt/weed-b`) **или** 2 volume nodes (volume1 healthy, volume2 fault target) |
| P5 | Возможность **безопасно** umount/remount/ro/fill **тестового** диска без production data |
| P6 | Master, filer, S3 Gateway, sideweed доступны по production-like path |
| P7 | **Никаких production данных** на тестовых дисках |
| P8 | Snapshot логов volume/master/sideweed до и после каждого сценария |
| P9 | Окно maintenance согласовано; rollback plan (remount, restart weed) готов |

---

## 3. Test environment layout

### A. Один volume node, несколько locations (рекомендуется для 4.3)

```
weed volume -dir=/mnt/weed-a,/mnt/weed-b -max=32,32 -mserver=<master> -ip=<vol-ip> -port=8080
```

- `/mnt/weed-a` — primary test fault target  
- `/mnt/weed-b` — must stay healthy для сценария F  
- Отдельные block devices или LVM volumes предпочтительнее bind-to-tmpfs

### B. Несколько volume nodes

```
volume1 (healthy) — все dirs OK
volume2 (fault)   — fault injection на /mnt/weed-a
```

- Master assign при `replication=001+` может уйти на volume1  
- На stand `replication=000` — проверять assign skip на **том же** node с multi-dir

### C. RAID / single mount — caveat

| Layout | Риск для теста |
|--------|----------------|
| RAID1/RAID10 один mount | Отказ «диска» может не дать per-dir isolation — **не подходит** для 4.3 без отдельных mount points |
| Один `-dir` | Нельзя проверить F (healthy sibling location) |
| LVM thin pool | `disk full` может вести себя иначе, чем ext4 на raw disk — документировать FS type |

**Рекомендация:** 2+ отдельных mount points на 2+ block devices.

---

## 4. Scenarios

Общий client path (как stand): **PUT** sideweed → S3; **GET** HAProxy/read → S3.  
Не использовать direct volume POST в acceptance (только debug).

---

### A. Baseline write/read

| | |
|---|---|
| **Цель** | Контрольная точка до отказов |
| **Setup** | Все dirs healthy; master/volumes/filer/s3/sideweed up |
| **Fault** | Нет |
| **Expected SeaweedFS** | PUT/GET OK; новые volumes на healthy dirs |
| **Expected master** | Все test volume IDs в `writables` |
| **Expected sideweed** | PUT 200; trace → S3 |
| **Logs** | Нет `marked unhealthy` |
| **PASS** | PUT + GET OK; `make test` эквивалент на remote client |
| **Recovery** | — |

---

### B. Disk mount unavailable

| | |
|---|---|
| **Цель** | ТЗ 4.2 — dir недоступен (umount / unplug / path missing) |
| **Setup** | Данные на vol IDs на `/mnt/weed-a`; `/mnt/weed-b` healthy |
| **Fault** | `umount /mnt/weed-a` (test disk only) или simulate disconnect |
| **Expected volume** | `/mnt/weed-a` → unhealthy; existing vols readonly; **no new volumes** on a |
| **Expected master** | Affected volume IDs removed from `writables`; assign на b |
| **Expected client** | PUT на **новые** объекты OK (через healthy dir); GET старых объектов на a — error или degraded |
| **Logs** | `marked unhealthy`, `existing volumes marked readonly: <ids>`, `disk health changed, sending heartbeat` |
| **PASS** | Unhealthy mark + master skip + PUT на healthy path OK |
| **Recovery** | См. H |

---

### C. Disk remount read-only

| | |
|---|---|
| **Цель** | ТЗ 4.2 — I/O error / read-only filesystem |
| **Setup** | Активные volumes на fault dir |
| **Fault** | `mount -o remount,ro /mnt/weed-a` |
| **Expected volume** | Следующая write → `marked unhealthy (io): read-only file system` |
| **Expected master** | Readonly heartbeat; assign skip |
| **Expected client** | PUT новых данных OK на healthy dir; PUT только на readonly vol — fail |
| **Logs** | `read-only file system`, volume IDs в log line |
| **PASS** | Совпадает с [seaweedfs-disk-health.md](seaweedfs-disk-health.md) примером лога |
| **Recovery** | H |

---

### D. Disk full

| | |
|---|---|
| **Цель** | ТЗ 4.2 — `isDiskSpaceLow` / write failure |
| **Setup** | Выделенный маленький test partition на `weed-a` |
| **Fault** | `fallocate` или `dd` до 100% fill **только test FS** |
| **Expected volume** | Unhealthy или readonly; `ReportDiskError` / low space path |
| **Expected master** | No assign на filled dir |
| **Expected client** | PUT через S3 OK если есть healthy dir; иначе fail |
| **Logs** | disk space / unhealthy / addVolume error |
| **PASS** | Writes stopped on full dir; healthy dir accepts writes |
| **Recovery** | Удалить fill file или expand FS → H |

---

### E. I/O error simulation

| | |
|---|---|
| **Цель** | ТЗ 4.2 — реальные I/O errors (не только ro) |
| **Setup** | Linux: `dmsetup` error target, `blkio` throttle, или fault injection (если доступно) |
| **Fault** | Inject EIO on test device **test-only** |
| **Expected volume** | `marked unhealthy (io)` |
| **Expected master** | Writable list update |
| **Expected client** | Depends on whether write hit faulted vol |
| **Logs** | `input/output error`, `LastError` in `/status` |
| **PASS** | Unhealthy + isolation как в C |
| **Recovery** | Remove fault layer → H |

*Если injection недоступен — минимум C + D обязательны; E optional.*

---

### F. One location unhealthy, another writable

| | |
|---|---|
| **Цель** | ТЗ **4.3** — изоляция: кластер продолжает писать |
| **Setup** | Multi-dir node; fault только `weed-a` |
| **Fault** | B, C или D на `weed-a` only |
| **Expected volume** | `FindFreeLocation` skips a; new volumes on b |
| **Expected master** | Assign только на volume IDs на b |
| **Expected client** | **PUT success** через production path (как `make chaos-multi-dir`) |
| **Logs** | `In dir /mnt/weed-b adds volume`; unhealthy on a |
| **PASS** | ≥1 successful PUT после fault; логи подтверждают запись на b |
| **Recovery** | H |

---

### G. All writable locations unavailable

| | |
|---|---|
| **Цель** | ТЗ 4.2 — полный отказ записи на node |
| **Setup** | Single-dir node **или** fault на все `-dir` |
| **Fault** | Все dirs unhealthy / full / umount |
| **Expected volume** | No healthy dir for writes |
| **Expected master** | No writable volumes on node |
| **Expected sideweed** | PUT **503** / `WRITE_DEGRADED` / `PUT_BLOCKED` (как `make test-sideweed` all-volumes-down) |
| **Logs** | sideweed write gate; master assign failures |
| **PASS** | PUT fails fast; нет silent data loss |
| **Recovery** | Restore ≥1 dir → H; затем PUT OK |

---

### H. Disk recovery / remount back

| | |
|---|---|
| **Цель** | ТЗ **4.5** — восстановление после устранения fault |
| **Setup** | После B–G |
| **Fault removal** | `mount` rw; free disk space; remove dm fault |
| **Expected volume** | `recovered and is healthy again; volumes restored to writable: <ids>` |
| **Expected master** | Volume IDs back in `writables` (heartbeat) |
| **Expected client** | PUT/GET OK |
| **Logs** | recovery line + `WRITE_RECOVERED` (sideweed) if was degraded |
| **PASS** | `/status` Healthy=true; successful PUT within 2× heartbeat interval |
| **Recovery** | — |

---

### I. Volume process must not crash

| | |
|---|---|
| **Цель** | ТЗ 4.2 — отказ диска не роняет `weed volume` |
| **Setup** | Любой fault B–G |
| **Fault** | As above |
| **Expected** | `weed volume` process **running**; `/healthz` or `/status` responds |
| **PASS** | `systemctl is-active` / `docker ps` / process exists; no OOM panic in logs |
| **Recovery** | H |

---

### J. Master must stop assigning to unhealthy location

| | |
|---|---|
| **Цель** | ТЗ **4.3** + 4.2 — master topology |
| **Setup** | Known volume IDs on fault dir |
| **Fault** | C or B |
| **Expected master** | `volume <id> remove from writable`; `/dir/assign` не возвращает ID на a |
| **Verification** | `scripts/debug/master_assign.sh` (debug only) или master logs + correlation with volume ID |
| **PASS** | Assign skips unhealthy dir volumes; new assign lands on healthy dir |
| **Recovery** | H → assign restores |

---

## 5. Commands / examples

> **⚠️ DANGEROUS — TEST HOST ONLY**  
> Замените `/mnt/weed-a`, device names и paths. **Не выполнять на production.**  
> Убедитесь, что на диске нет production data. Имейте console access.

### Mount / umount (test disk only)

```bash
# TEST ONLY — verify device with lsblk first
sudo umount /mnt/weed-a          # DANGEROUS: causes unavailable mount scenario B
sudo mount /dev/sdX /mnt/weed-a  # recovery H — use correct fstab entry
```

### Remount read-only

```bash
# TEST ONLY
sudo mount -o remount,ro /mnt/weed-a
# verify
mount | grep weed-a
touch /mnt/weed-a/.write-test && echo FAIL || echo "ro OK"
```

### Fill disk

```bash
# TEST ONLY — dedicated small partition strongly recommended
df -h /mnt/weed-a
sudo fallocate -l $(df -B1 --output=avail /mnt/weed-a | tail -1)B /mnt/weed-a/.fill-test 2>/dev/null || \
  sudo dd if=/dev/zero of=/mnt/weed-a/.fill-test bs=1M status=progress  # until ENOSPC
df -h /mnt/weed-a
```

### Health checks

```bash
curl -s http://<volume-ip>:8080/status | jq '.DiskHealth'
curl -s http://<master>:9333/dir/status | head
curl -sf http://<sideweed>:8880/v1/health
```

### Client smoke (from stand repo or production client)

```bash
# Production-like — NOT direct volume
./scripts/put_fragment.sh /tmp/test.bin camera-bm-test-$$
./scripts/get_fragment.sh camera-bm-test-$$ <fragment_uuid>
```

### Logs

```bash
journalctl -u seaweed-volume -f --since "5 min ago" | grep -iE 'disk location|unhealthy|recovered|readonly'
docker logs <volume-container> 2>&1 | grep -iE 'disk location|unhealthy|recovered'
```

---

## 6. Observability checklist

| Signal | Где искать | Связь с ТЗ |
|--------|------------|------------|
| Disk path / location | `disk location /mnt/weed-a` | 4.4 |
| I/O error text | `marked unhealthy (io)`, `LastError` in `/status` | 4.2, 4.4 |
| Unhealthy mark | `marked unhealthy`, `UnhealthySince` | 4.2 |
| Write stopped on dir | `new writes disabled on this directory` | 4.3 |
| Volume IDs affected | `existing volumes marked readonly: 3, 7` | 4.4 |
| Heartbeat sync | `disk health changed, sending heartbeat` | 4.3 |
| Master writable list | `remove from writable`, `not all writable` | 4.3 |
| Recovery | `recovered and is healthy again` | 4.5 |
| Sideweed gate | `PUT_BLOCKED`, `WRITE_DEGRADED`, `WRITE_RECOVERED` | 4.2, 4.5 |
| Prometheus | `seaweed_volumeServer_disk_healthy{dir}=0` | 4.4 |

---

## 7. PASS/FAIL matrix

| Scenario | Expected result | Required logs | Client PUT | Client GET | Recovery | Status field |
|----------|-----------------|---------------|------------|------------|----------|--------------|
| A baseline | All healthy | — | 200 | 200 | — | ☐ |
| B mount gone | a unhealthy; b writes | unhealthy + readonly IDs | 200 on b | old on a: fail/degraded | H restores | ☐ |
| C ro remount | a unhealthy (io) | read-only file system | 200 on b | — | H | ☐ |
| D disk full | a no writes | space/error | 200 on b | — | H | ☐ |
| E I/O inject | a unhealthy (io) | I/O error | 200 on b | — | H | ☐ |
| F partial fault | **Isolation** | unhealthy a + volume on b | **200** | 200 new obj | H | ☐ |
| G all dirs down | No assign | master/sideweed degrade | **503/fail** | existing may RO | H → PUT OK | ☐ |
| H recovery | Healthy=true | recovered + writable | 200 | 200 | — | ☐ |
| I no crash | Process up | no panic | — | — | — | ☐ |
| J master skip | No assign on a IDs | remove from writable | assign on b | — | H | ☐ |

**FAIL** = unhealthy not marked when fault applied; writes succeed **only** on faulted dir; volume process exit; master still assigns to readonly volumes; recovery does not restore writables within SLA.

Заполнять `Status` при выполнении: PASS / FAIL / SKIP (with reason).

---

### Enhanced local simulation (реализовано в stand repo)

Скрипты `scripts/disk-sim/` + [SEAWEEDFS-ENHANCED-DISK-SIMULATION.md](SEAWEEDFS-ENHANCED-DISK-SIMULATION.md):

| Техника | Статус |
|---------|--------|
| Loopback ext4 (`setup_loopback_dirs.sh`) | **Реализовано** |
| disk full / ro / umount / recover | **Реализовано**, **ручной прогон PASS** (2026-06-25) |
| `collect_logs.sh` | **Реализовано**, **ручной прогон PASS** |
| dm-error | Документировано; auto-run **нет** |

**Не заменяет** production bare-metal sign-off. Заказчик не предоставляет isolated node — destructive prod tests **запрещены**; только diagnostics / log collection или isolated test host.

---

## 8. Known limitations of Docker stand

| Topic | Stand behavior | Bare-metal needed |
|-------|----------------|-------------------|
| mount unavailable | `scripts/chaos/mount_unavailable.sh` often **WARN/SKIP** on tmpfs | Real umount / disconnect |
| disk full | fill may not propagate to weed view | Real ENOSPC on block FS |
| disk readonly | remount ro unreliable in container | Host remount ro |
| I/O errors | Hard to inject | dm-error / faulty hardware |
| Already covered | `make chaos-multi-dir` (partial dir fault), `make test-sideweed`, volume down failover | Confirms **client path**, not all disk semantics |
| matrix rows 2–4 | SKIP if fault not applied | Scenarios B–E |

---

## 9. Mapping to ТЗ

| ТЗ | Содержание | Уже в Docker stand | Подтверждает bare-metal |
|----|------------|--------------------|-------------------------|
| **4.2** | Обработка отказа диска | `chaos-multi-dir` (partial); volume down; test-sideweed | B, C, D, E, G — real FS/block errors |
| **4.3** | Изоляция damaged disk | multi-dir: write на /data2 при /data1 fault (если не SKIP) | F, J — guaranteed per-dir on real mounts |
| **4.4** | Логирование | Логи в docker при успешных сценариях | Полный checklist §6 на production-like host |
| **4.5** | Восстановление | `chaos-reset`, `make chaos-recovery*` | H — remount real disk, writables restore timing |

**Итог:** Docker stand доказывает **архитектуру и client path**; bare-metal — **обязательный** шаг для sign-off §4.2–4.5 на реальных дисках.

---

## 10. Execution record (template)

Заполнять при прогоне:

```
Date:
Host:
SeaweedFS commit: 1528e7d
Stand repo commit:
Tester:

Scenario | Result | Notes | Log file
---------|--------|-------|----------
A        |        |       |
...
```

---

## 11. Unit tests (pre-flight on fork)

Перед bare-metal прогоном на хосте с clone `seaweedfs`:

```bash
cd seaweedfs/weed
go test ./storage -run 'TestDiskLocationHealth|TestUnhealthyDirMarksExistingVolumesReadOnly|TestHeartbeatReportsUnhealthyDirVolumesReadOnly' -v
go test ./topology -run TestMasterAssignSkipsVolumesOnUnhealthyDiskDir -v
```

---

*Документ для Задачи №1 (SeaweedFS disk failure). Не заменяет [seaweedfs-disk-health.md](seaweedfs-disk-health.md).*
