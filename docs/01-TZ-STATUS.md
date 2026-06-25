# TZ status (§4–§8)

Internal acceptance tracker. **Not** a production sign-off.

## Legend

| Label | Meaning |
|-------|---------|
| **Done** | Implemented in repo |
| **Local verified** | Reproduced on Docker stand |
| **Partial** | Design or stand-only; prod gap remains |
| **Blocked** | Needs customer infra / change window |

## §4 SeaweedFS (Task №1)

| Req | Status | Evidence | Gap |
|-----|--------|----------|-----|
| 4.1 Customer fork | **Done** | Pin `1528e7d`, `make check-seaweedfs` | Deploy on physical nodes |
| 4.2 Disk failure handling | **Local verified** | `make chaos-multi-dir`, `scripts/disk-sim/` PASS 2026-06-25 | Bare-metal sign-off |
| 4.3 Per-dir isolation | **Local verified** | Multi-dir skip in patched `weed volume` | 14×`/mnt/stor*` on metal |
| 4.4 Logging / metrics | **Local verified** | Chaos logs, `seaweed_volumeServer_disk_healthy` | Prod host validation |
| 4.5 Recovery | **Local verified** | `recover_mounts.sh`, E2E overlay | Real remount SLA |

## §5 Cassandra (Task №2)

| Req | Status | Evidence | Gap |
|-----|--------|----------|-----|
| 5.1 vab/csb split | **Partial** | `make test-snapshot`; prod audit: camera still **vab** | Migration apply |
| 5.2 Pipeline | **Partial** | Stand scripts; prod configs read-only | streamserver/teye window |
| 5.3 Compaction / range query | **Partial** | `make test-range-query`; prod TWCS on `seaweedfs.filemeta` | teye DDL, `tablestats` |
| 5.4 Dual-read migration | **Not started** | Design in architecture doc | Customer data + job |

## §6 sideweed (Task №3)

| Req | Status | Evidence | Gap |
|-----|--------|----------|-----|
| 6.1 Health checks | **Local verified** | Blocking: s3, filer, master, assign; visibility: volume1/2 via `--write-health-visibility-check`; `make test-sideweed` **35/35** | Prod multi-S3-GW list |
| 6.2 PUT blocking | **Done** | 503 fail-fast on degraded write path | Prod rollout |
| 6.3 Recovery | **Done** (stand) | `WRITE_RECOVERED`, recovery threshold | Long soak |
| 6.4 Alerting | **Partial** | `/metrics`, `observability/vmalert-sideweed-rules.yml` | Customer vmalert deploy |

**§6.1 design:** write gate = aggregate **assign** readiness. Per-volume probes are **visibility-only** (`blocking: false` in JSON); single volume down must **not** block PUT when assign succeeds.

## §7 Testing

| Item | Status | Evidence |
|------|--------|----------|
| Stand smoke | **Local verified** | `make test`, `make test-snapshot`, `make test-range-query` |
| Write gate chaos | **Local verified** | `make test-sideweed` 35/35 |
| Docker chaos matrix | **Local verified** | `make chaos-matrix` (tmpfs limits on disk faults) |
| Host disk-sim | **Local verified** | full/ro/umount/recovery PASS 2026-06-25 |
| E2E disk-sim overlay | **Local verified** | `CONFIRM_DISK_SIM=1 make disk-sim-e2e-test` PASS |
| dm-error (I/O) | **Partial** | `make disk-sim-dm-error` — **SKIP** on dev host (`dm_mod` unavailable); manual on disposable VM |
| Bare-metal plan | **Blocked** | No isolated volume node from customer |

## §8 Deliverables

| Item | Status |
|------|--------|
| Stand repo, forks, scripts, docs | **Done** |
| Observability samples | **Done** (reference) |
| Production rollout | **Not done** |
| Bare-metal acceptance | **Not done** |

## Verified commands (latest)

```bash
make up && make health
make test && make test-snapshot && make test-range-query
make test-sideweed          # PASS=35
curl -fsS :8880/v1/write-health
curl -fsS :8880/metrics | grep sideweed_write_health_status
```

## Remaining (customer)

1. vmalert scrape + rules on VictoriaMetrics stack  
2. vab→csb migration (change window)  
3. teye Cassandra DDL / query patterns  
4. Bare-metal disk fault test on isolated volume node  
5. sideweed write gate on production write LB  
