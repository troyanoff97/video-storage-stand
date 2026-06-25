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

**Последнее обновление:** stand @ `336b451`, **синхронизирован с `origin/main`**. Fresh clone: **PASS** ([PUSH-CHECKLIST.md](PUSH-CHECKLIST.md)).

---

## 1. Назначение

Документ отвечает на вопрос: **что из исходного ТЗ уже сделано на stand**, что остаётся, и что заблокировано без production.  
Детали по задачам — в linked docs (см. §6).

---

## 2. Подтверждённый baseline

Подтверждено на stand и **fresh clone** (`video-storage-stand-fresh-metrics`):

| Область | Статус |
|---------|--------|
| Fresh clone | **PASS** — root `336b451`, sideweed `2a428d2`, seaweedfs `1528e7d` |
| Reproducibility | `make init-seaweedfs`, `make check-seaweedfs` (pin **`1528e7d`**) |
| Root repo | `github.com/troyanoff97/video-storage-stand` @ `origin/main` |
| SeaweedFS fork | `git@github.com:troyanoff97/seaweedfs.git`, branch `feat/volume-disk-health-isolation` |
| sideweed fork | submodule @ **`2a428d2`** на `origin/master` |
| Production-like path | sideweed → S3 → filer/master → volumes; read via HAProxy |

**Ключевые тесты (PASS):**

| Команда | Результат |
|---------|-----------|
| `go test ./...` | PASS |
| `make test` | PASS |
| `make verify-path` | PASS |
| `make test-sideweed` | PASS (**30/30**) |
| `make test-snapshot` | PASS |
| `make test-range-query` | PASS |
| `GET /v1/write-health`, `GET /metrics` | PASS на write sideweed |

**Push:** root и sideweed **опубликованы** на GitHub (см. [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md)).

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
| **6.1 Health checks** | **Partial** | Write probes; `/v1/write-health`; filer-down + **single/all volume** assign behavior in `test-sideweed` | [sideweed-health.md](sideweed-health.md), `make test-sideweed` | Direct per-volume probes; multi-master list; prod multi-S3-GW | — |
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
| **Source code (stand)** | **Done** | Repo + `pkg/fragment`, scripts, compose | README, tests PASS, `origin/main` | — | — |
| **SeaweedFS fork** | **Done** | Patched fork, pin, init scripts | [seaweedfs-customer-fork.md](seaweedfs-customer-fork.md) | Customer deploy on metal | — |
| **sideweed changes** | **Done** | Fork submodule: write gate, `/metrics`, `/v1/write-health` @ `2a428d2` | [sideweed-health.md](sideweed-health.md), `make test-sideweed` | Prod LB configs; per-volume probes | — |
| **Documentation** | **Done** | README, TZ deviations, task status docs, load model, checklists | `docs/*` | External customer report | — |
| **Build / deploy / test instructions** | **Done** | Makefile, [PRODUCTION-DEPLOY.md](PRODUCTION-DEPLOY.md), [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md) | `make help`, STAND-TESTING | Production rollout runbook execution | Customer env |

---

## 4. Текущие ограничения

- **Docker / tmpfs:** disk mount/ro/full часто **WARN/SKIP** в chaos-matrix; не заменяет physical disk (§4.2–4.5).
- **Production Cassandra DDL** не применялся — `schema-v2.cql` experimental, не runtime.
- **Нет streamserver / backend / LB** production configs для snapshots/archive.
- **Archive bucket** на stand: `video-fragments`, не ТЗ `vab`.
- **Metadata** archive + snapshots в одной runtime table `fragments`.
- **Alert delivery** не реализован — metrics и sample rules в `observability/`; см. [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md).
- **Production rollout** не выполнен — local/dev stand.
- **Cassandra §5.3 compaction** и **§5.4 migration** не в runtime.
- **Bare-metal disk test plan** — документ готов, **прогон не зафиксирован**.
- **sideweed:** direct per-volume probes и multi-master visibility — **gap** (см. §6.1).

---

## 5. Рекомендуемые следующие шаги

| Приоритет | Действие |
|-----------|----------|
| **A** | **Alerting delivery** — Alertmanager/webhook в prod stack |
| **B** | **Production validation Cassandra** — [CASSANDRA-CUSTOMER-QUESTIONS.md](CASSANDRA-CUSTOMER-QUESTIONS.md) |
| **C** | **Закрытие SeaweedFS §4** — [SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md](SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md) на test host |
| **D** | **Внешний отчёт** — сократить этот документ для заказчика |

---

## 6. Ссылки на документы

| Документ | Назначение |
|----------|------------|
| [README-STAND.md](../README-STAND.md) | Быстрый старт, архитектура |
| [CASSANDRA-TASK-STATUS.md](CASSANDRA-TASK-STATUS.md) | Задача №2 §5 |
| [CASSANDRA-LOAD-MODEL.md](CASSANDRA-LOAD-MODEL.md) | Capacity model |
| [CASSANDRA-CUSTOMER-QUESTIONS.md](CASSANDRA-CUSTOMER-QUESTIONS.md) | Checklist к заказчику |
| [SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md](SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md) | Задача №1 bare-metal |
| [seaweedfs-disk-health.md](seaweedfs-disk-health.md) | Disk-health патч |
| [sideweed-health.md](sideweed-health.md) | Write gate |
| [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md) | Alerting §6.4 (metrics + sample rules) |
| [STAND-TESTING.md](STAND-TESTING.md) | Тесты stand |
| [TZ-DEVIATIONS.md](TZ-DEVIATIONS.md) | Stand vs production |

---

*Внутренний документ. Design Cassandra: [CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md).*
