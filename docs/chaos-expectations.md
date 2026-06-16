# Chaos test expectations vs observed behavior on the local stand.
# Update after `make chaos-matrix` or `make chaos-volume1` runs.

## Application expectations (recommended)

| Event | App should |
|-------|------------|
| assign HTTP 406 | Retry with backoff; alert if persistent |
| assign connection refused (master down) | Circuit breaker; queue writes |
| PUT HTTP 5xx | Do not write Cassandra metadata; retry assign+put |
| GET via sideweed 502 | Retry on another read attempt (sideweed failover) |
| Cassandra insert fail after PUT | Compensating delete or mark orphan blob |

Go client (`pkg/fragment`): `AssignWithRetry` (406/5xx), `PutDirectWithRetry`, `GetViaSideweedWithRetry`, master circuit breaker (3 failures → open 10s). Unit tests: `make test-unit`.

## Topology notes (2026-06-16)

- **replication=001** requires both volume nodes in the **same dataCenter and rack** (`dc1` / `rack1`). With volume1 in `dc1` and volume2 in `dc2`, assign 001 fails on a fresh cluster.
- **Pin writes to volume1:** `replication=000` + stop volume2 (`make chaos-volume1` does this) or retry in `put_to_volume1.sh`.
- **disk read-only on volume1:** `docker-compose.chaos.yml` mounts **tmpfs** on volume1 `/data` (not a named volume) so `mount -o remount,ro` works; volume1 runs **privileged** for remount.

## Observed behavior (stand)

### volume1 stopped

- assign: **HTTP 406** — `No writable volumes and no free volumes left`
- PUT: not reached
- GET via sideweed: **HTTP 200** (replica on volume2)
- sideweed log: `"Status":"down"` for `http://volume1:8080`, DNS `server misbehaving`

### mount unavailable (chmod 000 /data on volume1)

- **Single `-dir` (default stand):** volume1 may **FATAL** on restart (`Check Data Folder Writable`) — does not demo per-dir patch; use multi-dir stand for isolation demo.
- assign: **HTTP 406** when no other writable capacity (pinned volume1)
- sideweed: volume1 marked DOWN after container crash

### all volumes down

- assign: **HTTP 000** (connection refused / no backend)
- PUT: **fail**
- GET via sideweed: **fail**

### sideweed down

- PUT (direct volume): **OK** (bypasses sideweed by design)
- GET via sideweed: **fail** (curl exit 7 / connection refused)

### recovery (`make chaos-recovery`)

- fault: volume1 stopped (volume2 stopped for pin) → assign **406**, PUT **fail**
- after `compose start volume1` + wait: assign **200**, PUT **OK** (tmpfs: baseline GET not asserted — data lost on restart)

### multi-dir (`make chaos-multi-dir`)

- volume1: `-dir=/data1,/data2` (see `docker-compose.multi-dir.yml`)
- fill or remount ro **/data1 only** → logs `marked unhealthy` for /data1
- PUT pinned to volume1 still **OK** (growth on /data2)
- after reset: `recovered and is healthy again` within ~60s

### disk full on volume1 (`make chaos-volume1`, tmpfs 512M)

- `disk_full.sh` fills tmpfs to ~100% (`/data/fill`).
- **Observed (2026-06-16):** PUT may still **succeed** if the needle fits in an already-open preallocated `.dat` volume (`volumeSizeLimitMB=256`). New volume growth fails when tmpfs is full.
- volume log when growth blocked: `no space left on device` / HTTP **500** on PUT (seen on earlier runs with host disk fill).
- **Mitigation:** `make clean && make up` between runs; or lower `-volumeSizeLimitMB` for chaos.

### disk read-only on volume1 (`make chaos-volume1`)

- `disk_readonly.sh`: `mount -t tmpfs -o remount,ro tmpfs /data` inside privileged volume1.
- assign: **HTTP 406** — `No writable volumes`
- PUT script: **exit 22** (assign failure)
- volume log: `open /data/NN.dat: read-only file system`
- GET of blobs written before remount: **HTTP 200** via sideweed (not re-tested in this run; expected)

### master stopped

- assign: **HTTP 000**, curl exit 7
- GET via sideweed: **HTTP 200** for known fid
- volume log: `heartbeat to master:9333 error: rpc error: code = Unavailable`

## Volume1 chaos run (`make chaos-volume1`, 2026-06-16)

| Step | Assign | PUT | Notes |
|------|--------|-----|-------|
| baseline (volume2 stopped) | 200 → volume1 | 201 | fid on volume1:8080 |
| disk full | 200 → volume1 | 201* | *may succeed on preallocated volume; see above |
| disk read-only | **406** | **fail (exit 22)** | logs: `read-only file system` |

Results file: `chaos-volume1-results.txt` (gitignored).

### Chaos matrix gates (`make chaos-matrix`)

Exit code 0 only if all checks pass. Scenarios 6–7 cover all volumes down and sideweed down. See [STAND-TESTING.md](STAND-TESTING.md).

### Pin assign to volume1

```bash
# stop volume2 so only volume1 accepts replication=000 writes:
docker compose -f docker-compose.yml -f docker-compose.chaos.yml stop volume2
./scripts/put_to_volume1.sh file.bin camera-1
make chaos-volume1   # stops volume2 automatically
```

```bash
REPLICATION=000 DATA_CENTER=dc1 ./scripts/put_fragment.sh file.bin camera-1
REPLICATION=000 ./bin/fragment put file.bin camera-1 --data-center dc1
```
