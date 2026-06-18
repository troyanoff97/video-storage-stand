# Chaos expectations (production S3 path)

Update after `make chaos-matrix` or `make chaos-multi-dir`.

All acceptance PUT/GET uses:
- **PUT:** `scripts/put_fragment.sh` → sideweed:8880 → S3 Gateway:8333
- **GET:** `scripts/get_fragment.sh` → HAProxy:8882 → sideweed-read → S3:8333

Write sideweed and read sideweed-read are **separate entrypoints**. Direct volume PUT is debug-only ([DEBUG.md](DEBUG.md)).

## Result labels (`make chaos-matrix`)

| Label | Meaning |
|-------|---------|
| **PASS** | Observed behavior matches production expectations |
| **WARN** | Fault simulation did not apply (tmpfs/remount limitation on stand) |
| **SKIP** | Check skipped because fault could not be reproduced |
| **FAIL** | Real production-path regression — unexpected success or failure |

Matrix exits non-zero only on **FAIL**.

## Sideweed (S3 upstream)

- Health: `GET /healthz` on S3 Gateway
- PUT proxied to `http://s3:8333` — trace log `"method":"PUT"`
- S3 down → sideweed 502, backend marked DOWN
- No per-request retry

## Matrix scenarios (`make chaos-matrix`)

Stand: `replication=000`, two volume nodes.

| # | Scenario | PUT (S3 via write sideweed) | GET (HAProxy → read path) |
|---|----------|----------------------------|---------------------------|
| 0 | baseline | PASS | PASS |
| 1 | volume1 down, volume2 up | **PASS** (failover to volume2) | PASS (existing object) |
| 2 | mount unavailable v1 (v2 stopped) | FAIL if fault applied; else SKIP | — |
| 3 | disk full v1 (v2 stopped) | FAIL if fault applied; else SKIP | — |
| 4 | disk ro v1 (v2 stopped) | FAIL if fault applied; else SKIP | PASS baseline after v2 restored |
| 5 | master down | **FAIL** (no new assign/write) | optional (existing object may PASS) |
| 6 | all volumes down | FAIL | FAIL |
| 7 | write sideweed down | FAIL | **PASS** (read via sideweed-read) |

### Why these expectations

- **volume1 down:** With `replication=000` and volume2 healthy, S3 can allocate on volume2 — PUT success is correct HA behavior, not a failure.
- **master down:** New writes need master assign → PUT must fail. GET of an already stored object may still work via filer/S3/volumes without master.
- **sideweed down:** Write entrypoint is down → PUT fails. Read uses HAProxy → sideweed-read → S3 → unaffected.
- **disk faults:** When tmpfs remount/fill cannot be applied, matrix logs **WARN** + **SKIP** instead of a false PASS/FAIL.

## Multi-dir (`make chaos-multi-dir`)

- baseline PUT-S3 OK
- /data1 fault → PUT-S3 still OK (writes via /data2)
- Logs: `marked unhealthy.*data1`, `In dir /data2 adds volume`
- sideweed trace: PUT → `s3:8333`

## Debug assign checks

Master `/dir/assign` tested only via `scripts/debug/master_assign.sh` in recovery/matrix diagnostics.

See [STAND-TESTING.md](STAND-TESTING.md).
