# Testing

## Quick start

```bash
make up && make health
make test              # archive PUT/GET via sideweed
make test-snapshot     # csb snapshots
make test-range-query  # Cassandra time range
make test-sideweed     # write gate (35 scenarios)
make verify-path       # log proof: sideweed→S3
```

**Stand credentials:** `stand_access_key` / `stand_secret_key` (dev defaults only).

## Production-path scripts

| Script | Path |
|--------|------|
| `put_fragment.sh` | sideweed:8880 → S3, `video-fragments` |
| `put_snapshot.sh` / `get_snapshot.sh` | write path, bucket `csb` |
| `get_fragment.sh` | HAProxy:8882 read |
| `list_fragments.sh` | Cassandra metadata |

Debug only: `scripts/debug/*` — never production path.

## `make test-sideweed`

| Failure | PUT | GET (read) |
|---------|-----|------------|
| master down | 503 | OK (existing) |
| all volumes down | 503 | FAIL |
| S3 / filer down | 503 | FAIL |
| single volume down | **200** | OK |
| recovered | 200 + `WRITE_RECOVERED` | OK |

**Volume visibility:** baseline checks `volume1`/`volume2` probes (`blocking: false`). When volume1 down: `volume1` probe `ok: false`, write gate stays **healthy**, no `PUT_BLOCKED`.

**Latest:** PASS=**35** FAIL=0.

## `make chaos-matrix`

Docker S3-path fault matrix. Disk faults on tmpfs often WARN/SKIP. Master/all-volumes/sideweed scenarios behave as expected.

## `make chaos-multi-dir`

Fault one `-dir` → PUT still OK via healthy sibling. Logs: `marked unhealthy`, assign on healthy dir.

## Host disk simulation (`scripts/disk-sim/`)

**Safety:** `DISK_SIM_ROOT=/tmp/seaweedfs-disk-sim`, `CONFIRM_DISK_SIM=1`, never touches `/mnt/stor*`.

| Target | Scenario |
|--------|----------|
| `disk-sim-setup` | loopback ext4 mounts |
| `disk-sim-full` | ENOSPC |
| `disk-sim-readonly` | remount ro |
| `disk-sim-mount-down` | umount |
| `disk-sim-recover` | remount |
| `disk-sim-cleanup` | teardown |
| `disk-sim-dm-error` | dm-error I/O (see below) |

**Verified PASS (2026-06-25):** setup, full, ro, umount, recovery, cleanup.

### dm-error (§7 I/O error)

`make disk-sim-dm-error` creates isolated dm-error device under `/tmp/seaweedfs-disk-sim/dm-error/`.

**Status on dev host:** **SKIP** — `dm_mod` unavailable in privileged docker root context. Not claimed as PASS.

**Manual:** run on disposable VM with `dmsetup` + `dm_mod`; see `scripts/disk-sim/README.md`.

## E2E disk-sim overlay

```bash
CONFIRM_DISK_SIM=1 make disk-sim-e2e-up
CONFIRM_DISK_SIM=1 make disk-sim-e2e-test
CONFIRM_DISK_SIM=1 make disk-sim-e2e-down
```

`docker-compose.disk-sim.yml` bind-mounts loopback dirs into volume1. **PASS** 2026-06-25 (compose project pin required).

## Bare-metal test plan

**Blocked** — customer has not provided isolated volume node.

Scenarios when available: baseline, umount, ro, disk full, I/O error, per-dir isolation (14 dirs), observability, recovery. PUT via sideweed→S3 only.

## Limitations

- Docker/tmpfs ≠ physical disks  
- 2 sim dirs ≠ 14 prod mounts  
- `schema-v2.cql` not in smoke path  
- dm-error not auto-verified on all hosts  
- No long soak / prod load tests  
