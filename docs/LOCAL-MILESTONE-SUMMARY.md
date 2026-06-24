# Local milestone summary (internal)

Краткая внутренняя сводка текущей локальной ветки.  
**Не для заказчика.** Детали — в linked docs.

---

## 1. Current local state

| Item | Value |
|------|-------|
| **Root repo** | HEAD `46a9589`, **ahead 13** of `origin/main`, working tree **clean** |
| **sideweed submodule** | HEAD `7eadd37`, **ahead 1** of `origin/master`, working tree **clean** |
| **Root → sideweed pointer** | `7eadd37` (`feat: expose Prometheus metrics`) |
| **sideweed on remote** | `origin/master` still @ `551df0b` until push |
| **SeaweedFS fork** | pin **`1528e7d`** — unchanged in this milestone |
| **Push** | **Not performed** (by policy) |

**Fresh-clone risk:** remote-only clone is temporarily **not reproducible** until sideweed `7eadd37` is pushed, then root. Safe order documented in [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md).

---

## 2. What this milestone includes

### Cassandra (Задача №2, §5)

| Deliverable | Status |
|-------------|--------|
| Optimization design | [CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md) |
| `schema-v2.cql` draft (experimental, not runtime) | [CASSANDRA-SCHEMA-V2.md](CASSANDRA-SCHEMA-V2.md) |
| Snapshot csb PUT/GET smoke | `make test-snapshot`, `scripts/test_snapshot.sh` |
| Range-query smoke | `make test-range-query`, `scripts/test_range_query.sh` |
| Load model | [CASSANDRA-LOAD-MODEL.md](CASSANDRA-LOAD-MODEL.md) |
| Customer questions checklist | [CASSANDRA-CUSTOMER-QUESTIONS.md](CASSANDRA-CUSTOMER-QUESTIONS.md) |
| Task status rollup | [CASSANDRA-TASK-STATUS.md](CASSANDRA-TASK-STATUS.md) |

Runtime `cassandra/schema.cql` and `docker-compose.yml` **not changed** for v2.

### SeaweedFS (Задача №1, §4)

| Deliverable | Status |
|-------------|--------|
| Bare-metal disk test plan | [SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md](SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md) |

Fork pin `1528e7d` already on customer remote; no new SeaweedFS push in this batch.

### sideweed (Задача №3, §6)

| Deliverable | Status |
|-------------|--------|
| Write gate (earlier commits, on remote @ `551df0b`) | [sideweed-health.md](sideweed-health.md) |
| **Phase 1:** Prometheus `/metrics` | sideweed `7eadd37`+ (local only until push) |
| **`GET /v1/write-health`** | JSON write gate visibility (sideweed `2a428d2`) |
| **Phase 2:** sample scrape + alert rules | `observability/prometheus-sideweed.yml`, `observability/sideweed-alert-rules.yml` |
| Alerting design | [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md) |

### Project / process

| Deliverable | Status |
|-------------|--------|
| TZ implementation status (internal) | [TZ-IMPLEMENTATION-STATUS.md](TZ-IMPLEMENTATION-STATUS.md) |
| Push readiness checklist (metrics batch) | [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md) |
| This milestone summary | this file |

---

## 3. Verified tests

**Last known PASS** on local `work2` stack (before/after docs-only commits; runtime unchanged):

| Command | Result |
|---------|--------|
| `make health` | PASS |
| `make test` | PASS |
| `make test-snapshot` | PASS |
| `make test-range-query` | PASS |
| `make verify-path` | PASS |
| `make test-sideweed` | PASS (17+/13+, includes `/metrics` + `/v1/write-health`) |
| `go test ./...` | PASS |
| `curl localhost:8880/metrics` | PASS (`sideweed_write_health_status`, `sideweed_backend_up`) |
| `curl localhost:8880/v1/write-health` | PASS (`status: healthy` when stack OK) |

**Not run** after latest docs/config commits: `make chaos-matrix` (no runtime change expected; previous matrix runs documented separately).

---

## 4. Current limitations

- **Push not performed** — 13 root commits + 1 sideweed commit local only.
- **Remote fresh clone** temporarily not reproducible until sideweed `7eadd37` → root push (see [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md)).
- **Alertmanager delivery** not implemented — metrics + sample rules only.
- **Cassandra production DDL** not applied — `schema-v2.cql` is design/draft.
- **Bare-metal disk tests** planned but **not executed** on physical hosts.
- **Production rollout** not done — local/dev stand only.
- **Customer-facing report** not prepared from this doc.

---

## 5. Next decision points

| Priority | Decision / action |
|----------|-------------------|
| 1 | **Push policy** — push sideweed `7eadd37`, then root; fresh-clone verify per [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md) |
| 2 | **Customer report** — distill [TZ-IMPLEMENTATION-STATUS.md](TZ-IMPLEMENTATION-STATUS.md) + task docs for Aziz/SRE (external wording) |
| 3 | **Cassandra prod data** — use [CASSANDRA-CUSTOMER-QUESTIONS.md](CASSANDRA-CUSTOMER-QUESTIONS.md) |
| 4 | **SeaweedFS §4 closure** — execute [SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md](SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md) on test metal |
| 5 | **Alerting delivery** — if customer monitoring stack known: wire Alertmanager/webhook from [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md) + `observability/` |

---

## 6. Links

| Document | Purpose |
|----------|---------|
| [TZ-IMPLEMENTATION-STATUS.md](TZ-IMPLEMENTATION-STATUS.md) | Full TZ status by section |
| [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md) | Safe push order + fresh-clone verification |
| [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md) | Metrics + sample alert rules |
| [CASSANDRA-TASK-STATUS.md](CASSANDRA-TASK-STATUS.md) | Cassandra task rollup |
| [SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md](SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md) | Disk fault tests on bare metal |

---

*Internal snapshot. Update when push policy or verified baseline changes.*
