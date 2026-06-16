# Chaos test expectations vs observed behavior on the local stand.
# Generated from make chaos-matrix runs; update after infrastructure changes.

## Application expectations (recommended)

| Event | App should |
|-------|------------|
| assign HTTP 406 | Retry with backoff; alert if persistent |
| assign connection refused (master down) | Circuit breaker; queue writes |
| PUT HTTP 5xx | Do not write Cassandra metadata; retry assign+put |
| GET via sideweed 502 | Retry on another read attempt (sideweed failover) |
| Cassandra insert fail after PUT | Compensating delete or mark orphan blob |

## Observed behavior (stand)

### volume1 stopped

- assign: **HTTP 406** — `No writable volumes and no free volumes left`
- PUT: not reached
- GET via sideweed: **HTTP 200** (replica on volume2)
- sideweed log: `"Status":"down"` for `http://volume1:8080`, DNS `server misbehaving`

### mount unavailable (chmod 000 /data on volume1)

- volume1: **FATAL** `Check Data Folder(-dir) Writable /data : Not writable!`
- assign: **HTTP 406** when no other writable capacity
- sideweed: volume1 marked DOWN after container crash

### disk full on volume1 (with `DATA_CENTER=dc1`)

- assign: **HTTP 406** or PUT **HTTP 500** / ENOSPC on volume1 logs
- Use: `DATA_CENTER=dc1 ./scripts/put_fragment.sh ...` or `make put-v1`

### disk read-only on volume1 (with `DATA_CENTER=dc1`)

- PUT: **HTTP 500**, volume log: `read-only file system`
- GET existing: **HTTP 200** via sideweed

### master stopped

- assign: **HTTP 000**, curl exit 7
- GET via sideweed: **HTTP 200** for known fid
- volume log: `heartbeat to master:9333 error: rpc error: code = Unavailable`

### Pin assign to volume1

Use **replication=000** + **dataCenter=dc1** (replication 001 requires a replica on another node):

```bash
./scripts/put_to_volume1.sh file.bin camera-1
REPLICATION=000 DATA_CENTER=dc1 ./scripts/put_fragment.sh file.bin camera-1
go run ./cmd/fragment put file.bin camera-1 --data-center dc1  # uses REPLICATION=001 by default; use env REPLICATION=000 for volume1-only
```
