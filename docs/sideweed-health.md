# Sideweed write degradation gate

Production **write** sideweed (`:8880`) blocks mutating requests when the SeaweedFS write path is unhealthy, without proxying PUT into S3 Gateway.

**Read** sideweed (`sideweed-read` behind HAProxy) is unchanged — no write gate.

## Architecture

```
PUT/POST/DELETE → sideweed:8880
  ├─ no S3 backend UP           → 503 PUT_BLOCKED reason=s3_backend_down (immediate)
  ├─ write health degraded      → 503 PUT_BLOCKED reason=write_health_degraded (immediate)
  └─ write health OK            → proxy → S3:8333 → filer → master → volumes

GET/HEAD → sideweed:8880 (if used) or HAProxy:8882 → sideweed-read → S3
  └─ not blocked by write gate (502 only if S3 backend fully DOWN)
```

## 502 vs 503

| Status | Source | When |
|--------|--------|------|
| **503** | Write gate | PUT/POST/DELETE while write path known unhealthy or no S3 backend for writes |
| **502** | LB proxy layer | GET (or requests without write gate) when all S3 backends are DOWN |

**Production expectation:** degraded write cluster → PUT always **503 fail-fast**, never 502.

The write gate runs **before** backend proxy selection for mutating methods, so S3 backend DOWN returns **503** on PUT (not 502).

## Write health probes

Enabled with `--write-health-enabled` and repeatable `--write-health-check=name=url[|code]`.

Stand (write sideweed):

| Probe | URL | Expected |
|-------|-----|----------|
| s3 | `http://s3:8333/healthz` | 200 |
| filer | `http://filer:8888/` | 200 |
| master | `http://master:9333/cluster/status` | 200 |
| assign | `http://master:9333/dir/assign?count=1&replication=000` | 200 |

Probes run **in parallel** with short timeout (default 1s). **First failed round** → `WRITE_DEGRADED` (no 2-round wait).

## State machine

| State | Meaning |
|-------|---------|
| `degraded` | Initial / after failed probes or S3 backend offline |
| `healthy` | After `recoveryThreshold` consecutive successful probe rounds |

Log events (with `-l --json`):

| Status | Reason field | Meaning |
|--------|--------------|---------|
| `WRITE_DEGRADED` | `master_down`, `assign_failed`, `all_volumes_down`, `s3_down`, `filer_down` | Write path unhealthy |
| `WRITE_RECOVERED` | — | Write path healthy again |
| `PUT_BLOCKED` | `s3_backend_down` or `write_health_degraded` | Individual mutating request rejected |

## Configuration flags

| Flag | Default | Description |
|------|---------|-------------|
| `--write-health-enabled` | off | Enable write gate |
| `--write-health-interval` | `health-duration` | Probe interval |
| `--write-unhealthy-threshold` | 1 | Failed rounds before WRITE_DEGRADED (1 = immediate on first failure) |
| `--write-recovery-threshold` | 2 | OK rounds before WRITE_RECOVERED |
| `--put-block-status` | 503 | Status for blocked writes |
| `--upstream-timeout` | 30s | Proxy dial timeout (does not affect known-degraded PUT block) |
| `--write-health-timeout` | 1s | Per-probe timeout |

## Blocked methods

`PUT`, `POST`, `DELETE` when write state is `degraded` or S3 backend is DOWN.

`GET`, `HEAD` are proxied normally if S3 upstream is UP; otherwise 502.

## Testing

```bash
make test-sideweed    # integration: 503 <1s, reason logs, recovery
cd sideweed && go test -v ./...   # unit tests
```

## Limitations (stand)

- Write gate only on **write** sideweed, not `sideweed-read`
- Volume health inferred via master `/dir/assign`, not per-volume `/status`
- S3 backend offline also triggers `WRITE_DEGRADED reason=s3_down` via backend health callback
- Threshold/interval tuned for docker stand

See [chaos-expectations.md](chaos-expectations.md), [STAND-TESTING.md](STAND-TESTING.md).
