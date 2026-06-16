# Stand testing — one-page checklist

Quick reference for validating the local stand (Task A) and the weed-volume disk-health patch (Task B).

## Prerequisites

```bash
cd /home/cerf/Desktop/work2
git submodule update --init --recursive
# SeaweedFS patches live in ./seaweedfs (local clone, not a GitHub fork)
test -d seaweedfs/weed || echo "clone seaweedfs first — see docs/seaweedfs-disk-health.md"
```

Requirements: Docker Compose v2, `curl`, `jq`, `make`, ~2 GB RAM.

## 1. Smoke (healthy stack)

```bash
make up && make health
make test          # bash put + get
make test-unit     # Go resilience unit tests
make test-go       # Go integration (stack must be up)
make test-all      # bash + integration
```

Expected: assign HTTP 200, PUT 201, GET via sideweed 200, Cassandra row present.

## 2. Chaos matrix (all fault scenarios + pass/fail)

```bash
make chaos-matrix
```

Writes `chaos-matrix-results.txt`. Exit code **0** = all gates passed.

| Step | Scenario | Expected gates |
|------|----------|----------------|
| 0 | baseline | PUT OK, fragment captured |
| 1 | volume1 down | PUT OK (volume2), GET OK |
| 2 | mount unavailable | PUT fail (pinned volume1) |
| 3 | disk full volume1 | PUT fail (pinned volume1) |
| 4 | disk read-only | PUT fail, GET OK (baseline) |
| 5 | master down | assign HTTP 000, GET OK |
| 6 | all volumes down | assign 000, PUT fail, GET fail |
| 7 | sideweed down | PUT OK, GET fail |

Reset between runs: `make chaos-reset` or `make clean && make up`.

## 3. Volume1-only chaos (disk full / read-only)

```bash
make chaos-volume1
```

Stops volume2, uses `replication=000` + `put_to_volume1.sh`. Results: `chaos-volume1-results.txt`.

## 4. Recovery automation

```bash
make chaos-recovery
```

Flow: disk read-only on volume1 → `reset_volumes.sh` → assign 200 → PUT/GET OK.  
Results: `chaos-recovery-results.txt`.

## 5. Multi-dir disk health (patch demo)

Proves per-`-dir` isolation on volume1 with `-dir=/data1,/data2`:

```bash
make chaos-multi-dir
# or: make up-multi-dir && ./scripts/chaos/run_multi_dir_chaos.sh
```

Results: `chaos-multi-dir-results.txt`. Checks:

- fill /data1 → PUT still OK (uses /data2)
- remount /data1 ro → logs `marked unhealthy`, PUT OK
- reset /data1 → logs `recovered and is healthy again`

## 6. SeaweedFS unit tests (patch, no Docker)

```bash
cd seaweedfs/weed
go test ./storage/... -run 'TestIsDiskError|TestDiskLocationHealth|TestFindFreeLocation|TestStartupUnhealthy|TestAddVolumeReportsDiskError' -v
```

## 7. Individual chaos scripts

```bash
make chaos-volume-down && make chaos-volume-up
make chaos-master-down && make chaos-master-up
make chaos-mount-unavailable && make chaos-reset
make chaos-disk-full && make chaos-reset
make chaos-disk-readonly && make chaos-reset
./scripts/chaos/all_volumes_down.sh && compose start volume1 volume2
./scripts/chaos/sideweed_down.sh && ./scripts/chaos/sideweed_up.sh
```

## Compose variants

| Files | Use |
|-------|-----|
| `docker-compose.yml` | base stack |
| `+ docker-compose.chaos.yml` | tmpfs /data, privileged volume1 (default `make up`) |
| `+ docker-compose.multi-dir.yml` | volume1 `-dir=/data1,/data2` |

## Where to read more

- [README-STAND.md](../README-STAND.md) — architecture, Makefile, observations
- [docs/chaos-expectations.md](chaos-expectations.md) — HTTP codes and log patterns
- [docs/seaweedfs-disk-health.md](seaweedfs-disk-health.md) — patch design and build
- [docs/seaweedfs-customer-fork.md](seaweedfs-customer-fork.md) — private fork setup (manual push)

## Agent policy

Local commits only; **no push** to remotes. Sideweed fork: `troyanoff97/sideweed`. SeaweedFS: local `./seaweedfs`.
