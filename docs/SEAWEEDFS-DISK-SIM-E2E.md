# SeaweedFS disk simulation — E2E overlay

**Status:** implemented (local only). Host loopback ext4 → docker bind mount → `weed volume -dir=/data1,/data2`.

**Связанные:** [SEAWEEDFS-ENHANCED-DISK-SIMULATION.md](SEAWEEDFS-ENHANCED-DISK-SIMULATION.md), `docker-compose.disk-sim.yml`, `scripts/disk-sim/e2e_*.sh`

---

## 1. Architecture

```
Host: /tmp/seaweedfs-disk-sim/mnt/stor1|stor2 (loop ext4)
        ↓ bind mount
Container volume1: -dir=/data1,/data2
        ↓
PUT: sideweed → S3 → filer → master → volumes
```

`volume2` остаётся на chaos tmpfs как дополнительный healthy node.

---

## 2. Safety

| Rule | Detail |
|------|--------|
| Paths | Только `${DISK_SIM_ROOT:-/tmp/seaweedfs-disk-sim}` |
| Confirm | `CONFIRM_DISK_SIM=1` обязателен |
| Main compose | `docker-compose.yml` **не меняется**; overlay отдельный файл |
| Volumes | **No** `docker compose down -v` |
| Restore | `e2e_down.sh` возвращает volume1 на chaos tmpfs |
| Compose project | **Должен совпадать** с running stand (см. §2.1) |

### 2.1 Compose project name

E2E скрипты управляют **тем же** compose project, что и активный stand. По умолчанию имя каталога (`work2`), но если stand поднят из другого clone/имени (напр. `video-storage-stand-fresh-metrics`), нужно:

```bash
export COMPOSE_PROJECT_NAME=video-storage-stand-fresh-metrics   # или auto-detect
```

Скрипты **авто-детектят** project по контейнеру `*-volume1-*` на порту `:8080`. При несовпадении — явная ошибка до recreate.

---

## 3. Commands

```bash
CONFIRM_DISK_SIM=1 make disk-sim-setup      # loopback mounts (sudo)
CONFIRM_DISK_SIM=1 make disk-sim-e2e-up     # recreate volume1 with binds
CONFIRM_DISK_SIM=1 make disk-sim-e2e-test   # baseline + faults + recovery
CONFIRM_DISK_SIM=1 make disk-sim-e2e-down   # restore volume1
CONFIRM_DISK_SIM=1 make disk-sim-cleanup    # teardown loopback
```

---

## 4. E2E scenarios (`e2e_test.sh`)

1. Preflight: volume1 bind-mounts `stor1`/`stor2` (fail-fast если `e2e_up` не применился)
2. Baseline PUT/GET via production path
3. Disk full on **stor1** → PUT still OK; volume logs show data1 fault / data2 assign
4. Read-only **stor1** → PUT OK via healthy path
5. Umount **stor1** → volume stays up; PUT via data2/volume2
6. `recover_mounts.sh` → PUT/GET PASS
7. `collect_logs.sh` after each phase (`DISK_SIM_E2E=1`)

---

## 5. Limitations

- Не bare-metal sign-off; bind mount через Docker ≠ production `/mnt/stor14`
- Пересоздание volume1 меняет volume slots на стенде (восстанавливается `e2e_down.sh`)
- Требует sudo для loopback setup/faults
- `dm-error` scenario — host sim only, не в E2E compose

---

## 6. Verification log

| Date | Operator | Result | Notes |
|------|----------|--------|-------|
| 2026-06-25 | manual | **PARTIAL** | см. §6.1 |

### 6.1 Ручной прогон 2026-06-25 (до fix compose project)

**Stand:** `video-storage-stand-fresh-metrics` (не `work2`). **Commit:** `f93ba31`.

| Step | Result | Notes |
|------|--------|-------|
| `disk-sim-setup` | **PASS** | loop10/11 → stor1/stor2 |
| `disk-sim-e2e-up` | **FAIL** | `Bind for 0.0.0.0:8080 failed` — создавался `work2-volume1-1`, порт занят `video-storage-stand-fresh-metrics-volume1-1` |
| `disk-sim-e2e-test` | **PARTIAL** | baseline/recovery PUT+GET **PASS**; host fault scripts **PASS**; **3× FAIL** log checks (volume1 без bind mounts → weed не видел host faults) |
| `disk-sim-e2e-down` | **FAIL** | тот же port conflict |
| `disk-sim-cleanup` | **PASS** | |
| sideweed smoke | **PASS** | write-health healthy |

**Root cause:** E2E скрипты не использовали compose project активного stand; `e2e_up` не применил overlay.

**Fix (post-`f93ba31`):** auto-detect `COMPOSE_PROJECT_NAME`, `stop/rm` перед recreate, preflight bind-mount check в `e2e_test`.

**Re-run required** для полного E2E PASS после fix.

---

*Enhanced host sim (без E2E bind) — [SEAWEEDFS-ENHANCED-DISK-SIMULATION.md](SEAWEEDFS-ENHANCED-DISK-SIMULATION.md) §12 **PASS**.*
