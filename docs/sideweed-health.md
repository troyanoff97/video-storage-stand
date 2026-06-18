# Sideweed write degradation gate

Production **write** sideweed (`:8880`) can block mutating requests when the SeaweedFS write path is unhealthy, without proxying PUT into S3 Gateway.

**Read** sideweed (`sideweed-read` behind HAProxy) is unchanged — no write gate.

## Architecture

```
PUT/POST/DELETE → sideweed:8880
  ├─ write health OK     → proxy → S3:8333 → filer → master → volumes
  └─ write health DOWN   → 503 PUT_BLOCKED (fail-fast, no upstream proxy)

GET/HEAD → sideweed:8880 (if used) or HAProxy:8882 → sideweed-read → S3
  └─ not blocked by write health gate
```

## Write health probes

Enabled with `--write-health-enabled` and repeatable `--write-health-check=name=url[|code]`.

Stand (write sideweed):

| Probe | URL | Expected |
|-------|-----|----------|
| s3 | `http://s3:8333/healthz` | 200 |
| filer | `http://filer:8888/` | 200 |
| master | `http://master:9333/cluster/status` | 200 |
| assign | `http://master:9333/dir/assign?count=1&replication=000` | 200 |

All probes must pass for **healthy** write state.

## State machine

| State | Meaning |
|-------|---------|
| `degraded` | Initial / after `unhealthyThreshold` consecutive failed probe rounds |
| `healthy` | After `recoveryThreshold` consecutive successful probe rounds |

Transitions logged (with `-l --json`):

- `DEGRADED` — write cluster cannot accept new writes
- `RECOVERED` — write cluster healthy again
- `PUT_BLOCKED` — individual PUT/POST/DELETE rejected at sideweed

## Configuration flags

| Flag | Default | Description |
|------|---------|-------------|
| `--write-health-enabled` | off | Enable write gate |
| `--write-health-interval` | `health-duration` | Probe interval |
| `--write-unhealthy-threshold` | 2 | Failed rounds → DEGRADED |
| `--write-recovery-threshold` | 2 | OK rounds → RECOVERED |
| `--put-block-status` | 503 | Status for blocked writes |
| `--upstream-timeout` | 30s | Proxy dial timeout |
| `--write-health-timeout` | 5s | Per-probe timeout |

## Blocked methods

`PUT`, `POST`, `DELETE` when write state is `degraded`.

`GET`, `HEAD`, and other methods are proxied normally if S3 upstream is UP.

## Testing

```bash
make test-sideweed    # integration: master/volumes/S3 faults + recovery logs
cd sideweed && go test -v ./...   # unit tests
```

## Limitations (stand)

- Write gate runs only on **write** sideweed instance, not `sideweed-read`
- Volume health inferred via master `/dir/assign`, not per-volume `/status`
- S3 upstream DOWN still yields 502 from LB layer (separate from write gate 503)
- Threshold/interval tuned for docker stand, not production load

See [chaos-expectations.md](chaos-expectations.md), [STAND-TESTING.md](STAND-TESTING.md).
