# Disk fault simulation (host loopback)

Enhanced **local** simulation of per-dir disk faults using loopback ext4 images under `/tmp/seaweedfs-disk-sim`.

**Not production sign-off.** Does not touch real `/mnt/stor*`.

## Requirements

- Linux: `losetup`, `mkfs.ext4`, `mount`, `umount`, `df`, `findmnt`, `dd`
- **sudo** for mount/umount/losetup (unless already root)
- `CONFIRM_DISK_SIM=1` for destructive steps

## Quick start

```bash
cd /home/cerf/Desktop/work2

# 1. Setup (sudo)
CONFIRM_DISK_SIM=1 ./scripts/disk-sim/setup_loopback_dirs.sh

# 2. Baseline logs (stand should be up: make up && make health)
./scripts/disk-sim/collect_logs.sh

# 3. Scenarios (one at a time; recover between)
CONFIRM_DISK_SIM=1 ./scripts/disk-sim/test_disk_full.sh
CONFIRM_DISK_SIM=1 ./scripts/disk-sim/recover_mounts.sh

CONFIRM_DISK_SIM=1 ./scripts/disk-sim/test_readonly_mount.sh
CONFIRM_DISK_SIM=1 ./scripts/disk-sim/recover_mounts.sh

CONFIRM_DISK_SIM=1 ./scripts/disk-sim/test_mount_unavailable.sh
CONFIRM_DISK_SIM=1 ./scripts/disk-sim/recover_mounts.sh

# 4. Cleanup
CONFIRM_DISK_SIM=1 ./scripts/disk-sim/cleanup_loopback_dirs.sh
```

Makefile targets: `make disk-sim-setup`, `make disk-sim-logs`, etc.

## Safety

- All mount paths must stay under `DISK_SIM_ROOT` (`safe_path` guard).
- Cleanup only removes `/tmp/seaweedfs-disk-sim`.
- Does not run `docker compose down -v`.

Full doc: [docs/SEAWEEDFS-ENHANCED-DISK-SIMULATION.md](../../docs/SEAWEEDFS-ENHANCED-DISK-SIMULATION.md).
