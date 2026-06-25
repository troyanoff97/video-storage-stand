# SeaweedFS disk simulation — E2E overlay

**Status:** implemented and **local verified PASS** (2026-06-25). Host loopback ext4 → docker bind mount → `weed volume -dir=/data1,/data2`.

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
| Compose project | **Pinned** до recreate (`pin_compose_project_from_running_stand`) |

### 2.1 Compose project name

Stand может работать не под именем каталога (`work2`), а под другим project (напр. `video-storage-stand-fresh-metrics`). Скрипты:

1. **Pin** `COMPOSE_PROJECT_NAME` по running `*-volume1-*` на `:8080` **до** `stop/rm volume1`
2. Auto-detect для `collect_logs` / `wait-healthy.sh`

При необходимости вручную:

```bash
export COMPOSE_PROJECT_NAME=video-storage-stand-fresh-metrics
```

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

1. Preflight: volume1 bind-mounts `stor1`/`stor2`
2. Baseline PUT/GET via production path
3. Disk full on **stor1** → PUT OK; volume logs data2 assign
4. Read-only **stor1** → PUT OK via healthy path
5. Umount **stor1** → volume stays up; PUT via data2/volume2
6. `recover_mounts.sh` → PUT/GET PASS
7. `collect_logs.sh` after each phase (`DISK_SIM_E2E=1`)

---

## 5. Limitations

- **Не** production bare-metal sign-off
- Bind mount через Docker ≠ physical `/mnt/stor14`
- Пересоздание volume1 меняет volume slots (восстанавливается `e2e_down.sh`)
- Требует sudo для loopback (или privileged Docker fallback в `run_root`)
- `dm-error` — host sim only

---

## 6. Verification log

| Date | Operator | Result | Notes |
|------|----------|--------|-------|
| 2026-06-25 | manual | **PARTIAL** | §6.1 — compose project bug (pre-`bce1bfb` follow-up) |
| 2026-06-25 | manual | **PASS** | §6.2 — после pin project + `bce1bfb` fixes |

### 6.1 Первый прогон (PARTIAL)

См. commit `f93ba31` / `bce1bfb` — project mismatch `work2` vs `video-storage-stand-fresh-metrics`.

### 6.2 Повторный прогон PASS (2026-06-25)

**Stand:** `video-storage-stand-fresh-metrics`. **Commits:** `bce1bfb` + pin-project fix.

| Step | Result |
|------|--------|
| `disk-sim-setup` | **PASS** (loopback ext4 stor1/stor2) |
| `disk-sim-e2e-up` | **PASS** — bind mounts verified, project pinned |
| `disk-sim-e2e-test` | **PASS** — все сценарии + collect_logs |
| `disk-sim-e2e-down` | **PASS** — volume1 restored to chaos tmpfs |
| `disk-sim-cleanup` | **PASS** |
| `make test-sideweed` | **PASS=30 FAIL=0** (с `COMPOSE_PROJECT_NAME` / auto-detect) |
| sideweed smoke | **PASS** |

**Проверено:** loopback ext4 → docker bind → `-dir=/data1,/data2` → baseline PUT/GET → disk full → read-only → umount → recovery → logs → cleanup → stand restored.

**Не проверено:** production bare-metal sign-off.

---

*Enhanced host sim (без E2E bind) — [SEAWEEDFS-ENHANCED-DISK-SIMULATION.md](SEAWEEDFS-ENHANCED-DISK-SIMULATION.md) §12 **PASS**.*
