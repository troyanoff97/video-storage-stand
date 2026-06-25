# Матрица приёмки по исходному ТЗ (internal)

Сводная матрица **requirement → evidence → status → gap** для stand repo.  
**Не акт сдачи** и **не сообщение заказчику**.

**Связанные документы:** [TZ-IMPLEMENTATION-STATUS.md](TZ-IMPLEMENTATION-STATUS.md), [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md), [SEAWEEDFS-ENHANCED-DISK-SIMULATION.md](SEAWEEDFS-ENHANCED-DISK-SIMULATION.md)

---

## Summary

| Область | Локально | Bare-metal / prod |
|---------|----------|-------------------|
| SeaweedFS §4 | Partial, local verified | **Blocked** (no customer metal) |
| Cassandra §5 | Partial, design + smoke | **Blocked** (teye DDL, migration) |
| sideweed §6 | Done / Partial | vmalert delivery pending |
| Testing §7 | Done on stand | E2E disk-sim overlay — design |
| Deliverables §8 | Done in repo | Production rollout **not done** |

---

## Legend

| Статус | Значение |
|--------|----------|
| **Done** | Реализовано и подтверждено на stand |
| **Partial / local verified** | Есть реализация или local proof; полное ТЗ не закрыто |
| **Blocked by customer infra** | Нужна среда/данные заказчика |
| **Not started** | Не реализовано |

---

## Раздел 4 — SeaweedFS

### 4.1 Fork SeaweedFS

| | |
|---|---|
| **Requirement** | Customer fork, disk-health patch, pin |
| **Implementation** | Fork `troyanoff97/seaweedfs`, branch `feat/volume-disk-health-isolation`, pin `1528e7d` |
| **Evidence** | [SEAWEEDFS_PIN.md](SEAWEEDFS_PIN.md), `make check-seaweedfs`, commits in fork |
| **Status** | **Done** |
| **Gap** | Customer deploy on physical nodes |
| **Next** | Bare-metal test plan execution when host available |

### 4.2 Disk failure handling

| | |
|---|---|
| **Requirement** | Detect disk full, ro, mount unavailable, I/O errors |
| **Implementation** | Patched `weed volume`; Docker chaos; **enhanced host sim** `scripts/disk-sim/` |
| **Evidence** | [seaweedfs-disk-health.md](seaweedfs-disk-health.md), `make chaos-multi-dir`, [SEAWEEDFS-ENHANCED-DISK-SIMULATION.md](SEAWEEDFS-ENHANCED-DISK-SIMULATION.md) §12 **PASS** |
| **Status** | **Partial / local verified** |
| **Gap** | Bare-metal sign-off **blocked**; dm-error manual only |
| **Next** | Customer isolated node or incident log review |

### 4.3 Unhealthy disk isolation

| | |
|---|---|
| **Requirement** | Writes skip faulted `-dir`; healthy dirs accept assigns |
| **Implementation** | Multi-dir logic in fork; prod audit: 14 `-dir` per node |
| **Evidence** | `make chaos-multi-dir`, [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md) §8, disk-sim ro/umount PASS |
| **Status** | **Partial / local verified** |
| **Gap** | Guaranteed per-dir on physical disk |
| **Next** | [SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md](SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md) |

### 4.4 Logging

| | |
|---|---|
| **Requirement** | Structured logs: path, volume IDs, heartbeat |
| **Implementation** | Fork logs + Prometheus metrics on volume |
| **Evidence** | [seaweedfs-disk-health.md](seaweedfs-disk-health.md), chaos-matrix logs |
| **Status** | **Partial / local verified** |
| **Gap** | Full sign-off on prod host |
| **Next** | [CUSTOMER-INCIDENT-DIAGNOSTICS.md](CUSTOMER-INCIDENT-DIAGNOSTICS.md) |

### 4.5 Recovery

| | |
|---|---|
| **Requirement** | Remount / recovery → writable, master restore |
| **Implementation** | Recovery loop; `chaos-reset`, `make chaos-recovery*`; disk-sim `recover_mounts.sh` |
| **Evidence** | Scripts, [SEAWEEDFS-ENHANCED-DISK-SIMULATION.md](SEAWEEDFS-ENHANCED-DISK-SIMULATION.md) |
| **Status** | **Partial / local verified** |
| **Gap** | Real disk remount SLA on metal |
| **Next** | Bare-metal scenario H |

---

## Раздел 5 — Cassandra / buckets

### 5.1 Bucket split (vab / csb)

| | |
|---|---|
| **Requirement** | Archive `vab`, camera snapshots `csb` |
| **Implementation** | Stand: `video-fragments` + `csb` smoke; prod audit: camera still **vab**, **csb** read-ready |
| **Evidence** | `make test`, `make test-snapshot`, [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md) §4 |
| **Status** | **Partial / local verified** |
| **Gap** | Production migration **not applied** |
| **Next** | [SNAPSHOT-BUCKET-MIGRATION-RUNBOOK.md](SNAPSHOT-BUCKET-MIGRATION-RUNBOOK.md) |

### 5.2 Pipeline configs

| | |
|---|---|
| **Requirement** | streamserver / teye / LB snapshot pipeline |
| **Implementation** | Prod configs audited (read-only); stand scripts only |
| **Evidence** | [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md), `put_snapshot.sh` / `get_snapshot.sh` |
| **Status** | **Partial** |
| **Gap** | Customer apply migration; streamserver/teye change window |
| **Next** | Runbook + customer sign-off |

### 5.3 Cassandra compaction

| | |
|---|---|
| **Requirement** | TWCS / partition optimization |
| **Implementation** | Prod `seaweedfs.filemeta` TWCS 6h; stand `schema-v2.cql` draft |
| **Evidence** | [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md) §5, [CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md) |
| **Status** | **Partial** |
| **Gap** | teye keyspace DDL, query patterns, `tablestats` |
| **Next** | [CASSANDRA-CUSTOMER-QUESTIONS.md](CASSANDRA-CUSTOMER-QUESTIONS.md) |

### 5.4 Compatibility

| | |
|---|---|
| **Requirement** | Dual-read / migration |
| **Implementation** | Design only |
| **Evidence** | [CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md) §6 |
| **Status** | **Not started** |
| **Gap** | Migration job, dual-write, customer data volume |
| **Next** | Customer DDL + SLA |

---

## Раздел 6 — sideweed

### 6.1 Health checks

| | |
|---|---|
| **Requirement** | Master + volume nodes health |
| **Implementation** | Write gate: s3, filer, master, **assign** (aggregate); `/v1/write-health` per-probe JSON |
| **Evidence** | [sideweed-health.md](sideweed-health.md), `make test-sideweed` **30/30** |
| **Status** | **Partial / local verified** |
| **Gap** | **Direct per-volume probes** — visibility only (design); must **not** block PUT when assign OK |
| **Next** | Optional future: non-gating volume metrics; see [sideweed-health.md](sideweed-health.md) § volume visibility |

### 6.2 PUT blocking

| | |
|---|---|
| **Requirement** | 503 fail-fast when write path degraded |
| **Implementation** | Write gate middleware |
| **Evidence** | `make test-sideweed`, sideweed `2a428d2` |
| **Status** | **Done** |
| **Gap** | Prod rollout |
| **Next** | Customer change window |

### 6.3 Automatic recovery

| | |
|---|---|
| **Requirement** | PUT OK after cluster recovery |
| **Implementation** | `WRITE_RECOVERED`, recovery threshold |
| **Evidence** | `make test-sideweed` recovery scenarios |
| **Status** | **Done** (stand) |
| **Gap** | Long soak / prod |
| **Next** | Soak test |

### 6.4 Logging / alerting

| | |
|---|---|
| **Requirement** | JSON logs + alerting |
| **Implementation** | `/metrics`, sample Prometheus + **vmalert** rules; prod stack VM/Grafana/vmalert |
| **Evidence** | [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md), [VMALERT-INTEGRATION.md](VMALERT-INTEGRATION.md), `observability/` |
| **Status** | **Partial / local verified** |
| **Gap** | vmalert **delivery** on customer stack |
| **Next** | Scrape + deploy rules |

---

## Раздел 7 — Testing

| | |
|---|---|
| **Requirement** | Local stand, fault scenarios, reproducibility |
| **Implementation** | `make up`, chaos-matrix, test-sideweed, disk-sim, fresh clone PASS |
| **Evidence** | [STAND-TESTING.md](STAND-TESTING.md), [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md) |
| **Status** | **Partial / local verified** |
| **Gap** | Bare-metal; E2E overlay **PARTIAL** (first run 2026-06-25, compose project fix applied) |
| **Next** | Re-run `disk-sim-e2e-*` after fix; bare-metal when host available |

---

## Раздел 8 — Deliverables

| | |
|---|---|
| **Requirement** | Code, docs, fork, instructions |
| **Implementation** | Stand repo, forks, docs suite, Makefile |
| **Evidence** | `README-STAND.md`, `docs/*`, `make help` |
| **Status** | **Done** (repo) |
| **Gap** | External customer report; production rollout |
| **Next** | Acceptance matrix → customer summary |

---

*Обновлять при смене verified baseline. Stand @ `02ac814` (ahead of origin).*
