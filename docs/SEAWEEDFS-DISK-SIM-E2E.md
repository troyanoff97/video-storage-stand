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

1. Baseline PUT/GET via production path
2. Disk full on **stor1** → PUT still OK; volume logs show data1 fault / data2 assign
3. Read-only **stor1** → PUT OK via healthy path
4. Umount **stor1** → volume stays up; PUT via data2/volume2
5. `recover_mounts.sh` → PUT/GET PASS
6. `collect_logs.sh` after each phase (`DISK_SIM_E2E=1`)

---

## 5. Limitations

- Не bare-metal sign-off; bind mount через Docker ≠ production `/mnt/stor14`
- Пересоздание volume1 меняет volume slots на стенде (восстанавливается `e2e_down.sh`)
- Требует sudo для loopback setup/faults
- `dm-error` scenario — host sim only, не в E2E compose

---

*Manual verification: record results in §6 below after each run.*

## 6. Verification log

| Date | Operator | Result | Notes |
|------|----------|--------|-------|
| | | | |
