# Статус реализации по исходному ТЗ (internal)

Сводный внутренний статус stand repo и связанных fork'ов.  
**Не финальный акт сдачи** и **не сообщение заказчику**.

**Статусы:**

| Статус | Значение |
|--------|----------|
| **Done** | Реализовано и подтверждено тестами/docs на stand |
| **Partial** | Есть реализация или design, не полное закрытие ТЗ |
| **Not done** | Не реализовано |
| **Blocked** | Требуются данные/среда заказчика или bare-metal |

**Последнее обновление:** stand @ `77bd2cd`, branch **ahead 12** (push не выполнялся). Push readiness: [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md) (metrics batch).

---

## 1. Purpose

Документ отвечает на вопрос: **что из исходного ТЗ уже сделано на stand**, что остаётся, и что заблокировано без production.  
Детали по задачам — в linked docs (см. §6).

---

## 2. Verified baseline

Подтверждено на локальном stand (последние прогоны):

| Область | Статус |
|---------|--------|
| Fresh clone | Ранее **PASS**; **сейчас** remote-only clone неполон до push sideweed `7eadd37` + root (см. [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md)) |
| Reproducibility | `make init-seaweedfs`, `make check-seaweedfs` (pin **`1528e7d`**) |
| Root repo | `github.com/troyanoff97/video-storage-stand` |
| SeaweedFS fork | `git@github.com:troyanoff97/seaweedfs.git`, branch `feat/volume-disk-health-isolation` |
| sideweed fork | `github.com/troyanoff97/sideweed` (submodule) |
| Production-like path | sideweed → S3 → filer/master → volumes; read via HAProxy |

**Key tests (PASS на чистом `work2` стеке):**

| Command | Result |
|---------|--------|
| `go test ./...` | PASS |
| `make test` | PASS |
| `make verify-path` | PASS |
| `make test-sideweed` | PASS (13/13; metrics check included) |
| `make test-snapshot` | PASS |
| `make test-range-query` | PASS |

**Push:** последние **12** локальных commits **не pushed** к `origin/main`. Порядок и fresh-clone plan: [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md) — push **не выполнялся**.

---

## 3. Статус по ТЗ

### Раздел 4 — Задача №1 SeaweedFS (disk failure / isolation)

| Пункт | Статус | Что сделано | Подтверждение | Что осталось | Блокер |
|-------|--------|-------------|---------------|--------------|--------|
| **4.1 Fork SeaweedFS** | **Done** | Customer fork, branch `feat/volume-disk-health-isolation`, pin `1528e7d` | [SEAWEEDFS_PIN.md](SEAWEEDFS_PIN.md), `make check-seaweedfs`, commits `af95554`+ | Push policy / customer remote sync | — |
| **4.2 Обработка отказа диска** | **Partial** | Патч volume: unhealthy dir, readonly volumes, I/O / space errors | Unit tests in fork; `make chaos-multi-dir`; [seaweedfs-disk-health.md](seaweedfs-disk-health.md) | Real mount/ro/full/I/O on bare metal | Docker tmpfs → matrix WARN/SKIP |
| **4.3 Изоляция damaged disk** | **Partial** | Multi-dir skip; master removes writables; writes on healthy dir | `make chaos-multi-dir` when fault applies | Guaranteed per-dir on physical disk | Same as 4.2 |
| **4.4 Логирование** | **Partial** | Structured logs: path, volume IDs, heartbeat, `/status`, Prometheus metric | [seaweedfs-disk-health.md](seaweedfs-disk-health.md) | Full sign-off on prod host | Bare-metal run |
| **4.5 Восстановление** | **Partial** | Recovery loop + heartbeat; `chaos-reset`, recovery scripts | `make chaos-recovery*`, log `recovered and is healthy again` | Remount real disk timing SLA | Bare-metal scenario H |

**Runbook:** [SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md](SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md)

---

### Раздел 5 — Задача №2 Cassandra (metadata optimization)

| Пункт | Статус | Что сделано | Подтверждение | Что осталось | Блокер |
|-------|--------|-------------|---------------|--------------|--------|
| **5.1 Bucket separation vab/csb** | **Partial** | Blob: archive `video-fragments`, snapshots `csb` | `make test`, `make test-snapshot` | Production bucket `vab`; metadata split | Customer bucket layout |
| **5.2 Snapshot pipeline write/read csb** | **Partial** | `put_snapshot.sh`, `get_snapshot.sh`, `make test-snapshot` | commit `9f134a1`, smoke PASS | streamserver/backend/LB; metadata store | Production configs |
| **5.3 Compaction optimization** | **Partial** | Design + `schema-v2.cql` TWCS draft | `5877202`, [CASSANDRA-LOAD-MODEL.md](CASSANDRA-LOAD-MODEL.md) | Runtime TWCS/TTL tuning | Production DDL + `tablestats` |
| **5.3 Segment search / range query** | **Partial** | `fragment list`, `list_fragments.sh`, `make test-range-query` | commit `4e2e0b6`, smoke PASS | `time_bucket` / v2 at scale | Production query patterns |
| **5.4 Compatibility** | **Not done** | Dual-read/migration описаны в design | [CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md) | Migration job, dual-write code | Production DDL + data volume |

**Сводка задачи №2:** [CASSANDRA-TASK-STATUS.md](CASSANDRA-TASK-STATUS.md)

---

### Раздел 6 — Задача №3 sideweed

| Пункт | Статус | Что сделано | Подтверждение | Что осталось | Блокер |
|-------|--------|-------------|---------------|--------------|--------|
| **6.1 Health checks** | **Partial** | Write probes (S3, filer, master, assign); `GET /v1/write-health`; **filer-down** in `make test-sideweed` | [sideweed-health.md](sideweed-health.md), `make test-sideweed` | Direct per-volume probes; multi-master list; prod multi-S3-GW | — |
| **6.2 PUT blocking** | **Done** | 503 fail-fast `PUT_BLOCKED` / `write_health_degraded` | `make test-sideweed`, commit `1d9e0f0`, `77eea5c` | — | — |
| **6.3 Automatic recovery** | **Done** | PUT OK after master/S3/volumes recovery; `WRITE_RECOVERED` | `make test-sideweed` recovery scenarios | Long soak / prod soak | — |
| **6.4 Logging / alerting** | **Partial** | JSON logs; Phase 1 `/metrics`; Phase 2 sample Prometheus scrape + alert rules | [sideweed-health.md](sideweed-health.md); [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md); [observability/](../observability/); `make test-sideweed` | Alertmanager delivery, webhook/Slack, prod monitoring stack | Customer monitoring stack |

---

### Раздел 7 — Testing

| Пункт | Статус | Что сделано | Подтверждение | Что осталось | Блокер |
|-------|--------|-------------|---------------|--------------|--------|
| **Local stand** | **Done** | `make up`, health, smoke tests | [STAND-TESTING.md](STAND-TESTING.md), fresh clone PASS | — | — |
| **Disk fault** | **Partial** | `make chaos-matrix`, `chaos-multi-dir` | [chaos-expectations.md](chaos-expectations.md) | Bare-metal B–G | tmpfs/remount limits |
| **Disk recovery** | **Partial** | `chaos-reset`, `make chaos-recovery*` | Scripts + docs | Real disk remount H | Bare metal |
| **SeaweedFS unavailable** | **Done** | master/volumes/S3 down scenarios | `make test-sideweed`, chaos-matrix | — | — |
| **sideweed behavior** | **Done** | Write gate + read path separation | `make test-sideweed`, matrix #7 | — | — |

---

### Раздел 8 — Deliverables

| Пункт | Статус | Что сделано | Подтверждение | Что осталось | Блокер |
|-------|--------|-------------|---------------|--------------|--------|
| **Source code (stand)** | **Done** | Repo + `pkg/fragment`, scripts, compose | README, tests PASS | Push ahead 8 commits | Push policy |
| **SeaweedFS fork** | **Done** | Patched fork, pin, init scripts | [seaweedfs-customer-fork.md](seaweedfs-customer-fork.md) | Customer deploy on metal | — |
| **sideweed changes** | **Done** | Fork in submodule, write gate | [sideweed-health.md](sideweed-health.md) | Prod LB configs | — |
| **Documentation** | **Done** | README, TZ deviations, task status docs, load model, checklists | `docs/*` | External customer report | — |
| **Build / deploy / test instructions** | **Done** | Makefile, [PRODUCTION-DEPLOY.md](PRODUCTION-DEPLOY.md), [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md) | `make help`, STAND-TESTING | Production rollout runbook execution | Customer env |

---

## 4. Current limitations

- **Docker / tmpfs:** disk mount/ro/full часто **WARN/SKIP** в chaos-matrix; не заменяет physical disk (§4.2–4.5).
- **No production Cassandra DDL** — `schema-v2.cql` experimental, не runtime.
- **No streamserver / backend / LB** production configs для snapshots/archive.
- **Archive bucket** на stand: `video-fragments`, не ТЗ `vab`.
- **Metadata** archive + snapshots в одной runtime table `fragments`.
- **No alert delivery** на stand — metrics scrapeable; sample rules in `observability/`; delivery: [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md)
- **No production rollout** — только local/dev stand.
- **Latest 12 commits not pushed** to `origin/main`; push readiness documented in [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md), push not performed
- **Cassandra §5.3 compaction** и **§5.4 migration** не в runtime.
- **Bare-metal disk test plan** — документ готов, **прогон не зафиксирован** в этом status.

---

## 5. Recommended next steps

| Приоритет | Действие |
|-----------|----------|
| **A** | **Push policy** — при необходимости: sideweed `7eadd37` first, then root (см. [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md)); без заказчика — держать локально |
| **B** | **Alerting delivery** — Alertmanager/webhook в prod stack (metrics + sample rules готовы) |
| **C** | **Production validation Cassandra:** запросить данные по [CASSANDRA-CUSTOMER-QUESTIONS.md](CASSANDRA-CUSTOMER-QUESTIONS.md) |
| **D** | **Закрытие SeaweedFS §4:** выполнить [SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md](SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md) на test host |
| **E** | **Внешний отчёт:** сократить этот документ + [CASSANDRA-TASK-STATUS.md](CASSANDRA-TASK-STATUS.md) для заказчика (после ревью) |

---

## 6. Links to existing docs

| Документ | Назначение |
|----------|------------|
| [README-STAND.md](../README-STAND.md) | Быстрый старт, архитектура |
| [CASSANDRA-TASK-STATUS.md](CASSANDRA-TASK-STATUS.md) | Задача №2 §5 |
| [CASSANDRA-LOAD-MODEL.md](CASSANDRA-LOAD-MODEL.md) | Capacity model |
| [CASSANDRA-CUSTOMER-QUESTIONS.md](CASSANDRA-CUSTOMER-QUESTIONS.md) | Checklist к заказчику |
| [SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md](SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md) | Задача №1 bare-metal |
| [seaweedfs-disk-health.md](seaweedfs-disk-health.md) | Disk-health патч |
| [sideweed-health.md](sideweed-health.md) | Write gate |
| [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md) | Alerting proposal §6.4 |
| [STAND-TESTING.md](STAND-TESTING.md) | Тесты stand |
| [TZ-DEVIATIONS.md](TZ-DEVIATIONS.md) | Stand vs production |

---

*Internal document. Для детального design Cassandra см. [CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md).*
