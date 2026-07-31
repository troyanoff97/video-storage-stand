# Delivery summary

Customer-facing overview of the video-storage stand work.

## Scope

1. **SeaweedFS** — disk failure handling on customer fork (per-dir isolation)  
2. **Cassandra** — `seaweedfs.filemeta` TWCS 6h→2d artifacts + runbook (teye out of scope)  
3. **sideweed** — write protection (503 on degraded path) + observability  
4. **Этап 4** — working SLA (no formal), autonomy, min/rec hardware (`docs/08-SLA-AND-HARDWARE.md`)  

## Delivered

| Artifact | Status |
|----------|--------|
| Stand repo (`video-storage-stand`) | Done |
| SeaweedFS fork @ `af88c7f` | Done |
| sideweed fork (write gate, `/metrics`, `/v1/write-health`, volume visibility) | Done |
| Tests, disk-sim, chaos scripts | Done |
| vmalert rule samples (`observability/`) | Done (reference) |
| Incident collector script | Done |
| vab→csb migration runbook | Prepared, **not applied** |
| `filemeta` TWCS 2d ALTER/rollback + analysis | Prepared, **not applied** |
| SLA / hardware / autonomy docs | Done (working targets; no formal SLA) |

## Verified on stand

- Production-like write/read paths (sideweed → S3; HAProxy read)  
- `make test`, `make test-snapshot`, `make test-range-query`  
- `make test-sideweed` — **35/35** (write gate + volume visibility probes)  
- Host disk-sim + E2E overlay — **PASS** 2026-06-25  
- Production configs audited read-only (no secrets in repo)  

```bash
git submodule update --init --recursive
SEAWEEDFS_REPO_URL=git@github.com:troyanoff97/seaweedfs.git make init-seaweedfs
make check-seaweedfs && make up && make test && make test-sideweed
```

## Production alignment (read-only audit)

- Write/read topology matches stand model  
- 14 data dirs per volume node — patch directly relevant  
- Camera snapshots still in **vab**; **csb** read infra ready  
- Monitoring: VictoriaMetrics/Grafana/vmalert — sideweed metrics compatible  

## Not claimed

- **Bare-metal** disk fault sign-off  
- **Production rollout** of fork or write gate  
- **Alert delivery** live in any environment  
- **csb write migration** applied  
- **dm-error** auto-verified on all hosts (optional SKIP on dev)  

## Remaining (needs customer)

| Item | Why |
|------|-----|
| Fold `filemeta` TWCS 2d into main playbook | ad-hoc done in some envs; CQL/runbook ready |
| Bare-metal disk tests | no isolated host |
| csb migration apply | change window |
| vmalert deploy | SRE integration |
| sideweed prod rollout | write LB change window (if still pending) |

## Repositories

- Stand: `github.com/troyanoff97/video-storage-stand`
- SeaweedFS: `github.com/troyanoff97/seaweedfs` (`feat/volume-disk-health-isolation`, `af88c7f`)
- sideweed: `github.com/troyanoff97/sideweed` (submodule pointer in stand)

## Documentation map

| Doc | Contents |
|-----|----------|
| [01-TZ-STATUS.md](01-TZ-STATUS.md) | Requirement status §4–§8 |
| [02-ARCHITECTURE.md](02-ARCHITECTURE.md) | Paths, forks, health model |
| [03-TESTING.md](03-TESTING.md) | Commands, chaos, disk-sim |
| [04-OPERATIONS.md](04-OPERATIONS.md) | Metrics, alerts, incidents |
| [05-PRODUCTION-RUNBOOKS.md](05-PRODUCTION-RUNBOOKS.md) | Deploy, migration, `filemeta` TWCS, push |
| [07-CASSANDRA-FILEMETA.md](07-CASSANDRA-FILEMETA.md) | Prod baseline, TWCS 2d analysis |
| [08-SLA-AND-HARDWARE.md](08-SLA-AND-HARDWARE.md) | Working SLA, autonomy, hardware |
| This file | Executive summary |
