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

**Последнее обновление:** stand @ `02ac814` (local, ahead 4). Матрица приёмки: [TZ-ACCEPTANCE-MATRIX.md](TZ-ACCEPTANCE-MATRIX.md). Production config audit: [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md).

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
| **4.2 Обработка отказа диска** | **Partial** | Патч volume; prod 14 `-dir`; **enhanced host sim** | [SEAWEEDFS-ENHANCED-DISK-SIMULATION.md](SEAWEEDFS-ENHANCED-DISK-SIMULATION.md), `scripts/disk-sim/` | Bare-metal sign-off | Customer metal host |
| **4.3 Изоляция damaged disk** | **Partial** | Multi-dir skip; master removes writables; writes on healthy dir | `make chaos-multi-dir` when fault applies | Guaranteed per-dir on physical disk | Same as 4.2 |
| **4.4 Логирование** | **Partial** | Structured logs: path, volume IDs, heartbeat, `/status`, Prometheus metric | [seaweedfs-disk-health.md](seaweedfs-disk-health.md) | Full sign-off on prod host | Bare-metal run |
| **4.5 Восстановление** | **Partial** | Recovery loop + heartbeat; `chaos-reset`, recovery scripts | `make chaos-recovery*`, log `recovered and is healthy again` | Remount real disk timing SLA | Bare-metal scenario H |

**Runbook:** [SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md](SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md)

---

### Раздел 5 — Задача №2 Cassandra (metadata optimization)

| Пункт | Статус | Что сделано | Подтверждение | Что осталось | Блокер |
|-------|--------|-------------|---------------|--------------|--------|
| **5.1 Bucket separation vab/csb** | **Partial** | Stand: `video-fragments`/`csb`; prod audit: **vab** archive+camera snapshots, **csb** read-ready | `make test`, `make test-snapshot`; [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md) | Prod write migration vab→csb | Customer apply |
| **5.2 Snapshot pipeline write/read csb** | **Partial** | Stand smoke; prod: camera snapshots в **vab**, events в **esb** | `make test-snapshot`; prod configs | streamserver `bucket_name`; teye `camera_base_url` | Customer migration |
| **5.3 Compaction optimization** | **Partial** | Prod **`seaweedfs.filemeta` TWCS 6h**; stand `schema-v2.cql` draft (app layer) | [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md) §5 | teye DDL; app metadata tuning | teye Cassandra |
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
| **6.4 Logging / alerting** | **Partial** | JSON logs; `/metrics`; Prometheus + **vmalert** sample rules; prod stack: **VictoriaMetrics/Grafana/vmalert** | [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md), [VMALERT-INTEGRATION.md](VMALERT-INTEGRATION.md), `observability/vmalert-sideweed-rules.yml` | vmalert **deploy** на customer stack; prod write gate rollout | Customer SRE |

---

### Раздел 7 — Testing

| Пункт | Статус | Что сделано | Подтверждение | Что осталось | Блокер |
|-------|--------|-------------|---------------|--------------|--------|
| **Local stand** | **Done** | `make up`, health, smoke tests | [STAND-TESTING.md](STAND-TESTING.md), fresh clone PASS | — | — |
| **Disk fault** | **Partial** | `chaos-matrix`, `chaos-multi-dir`; **enhanced host sim** `scripts/disk-sim/` — ручной прогон **PASS** (2026-06-25) | [SEAWEEDFS-ENHANCED-DISK-SIMULATION.md](SEAWEEDFS-ENHANCED-DISK-SIMULATION.md) §12 | Bare-metal B–G sign-off; [SEAWEEDFS-DISK-SIM-E2E.md](SEAWEEDFS-DISK-SIM-E2E.md) overlay | Customer metal host |
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
- **Production Cassandra DDL** частично получен: **`seaweedfs.filemeta`** (TWCS); teye keyspace DDL — **нет**. Stand `schema-v2.cql` — experimental.
- **Production configs получены** (read-only audit); **изменения в prod не внесены**.
- **Нет bare-metal** test host от заказчика.
- **Archive bucket** на stand: `video-fragments`, не ТЗ `vab`.
- **Metadata** archive + snapshots в одной runtime table `fragments`.
- **Alert delivery** не реализован — metrics и sample rules в `observability/`; см. [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md).
- **Production rollout** не выполнен — local/dev stand.
- **Cassandra §5.3 compaction** и **§5.4 migration** не в runtime.
- **Bare-metal disk test** — заказчик не предоставляет host; **enhanced local sim** (`scripts/disk-sim/`) добавлен; **не** заменяет physical sign-off.
- **sideweed:** direct per-volume probes и multi-master visibility — **gap** (см. §6.1).

---

## 5. Рекомендуемые следующие шаги

| Приоритет | Действие |
|-----------|----------|
| **A** | **vmalert deploy** — customer scrape + `observability/vmalert-sideweed-rules.yml` ([VMALERT-INTEGRATION.md](VMALERT-INTEGRATION.md)) |
| **B** | **Snapshot vab→csb** — [SNAPSHOT-BUCKET-MIGRATION-RUNBOOK.md](SNAPSHOT-BUCKET-MIGRATION-RUNBOOK.md) (apply в change window) |
| **C** | **teye Cassandra** — запросить DDL/query patterns |
| **D** | **SeaweedFS §4** — прогон [SEAWEEDFS-ENHANCED-DISK-SIMULATION.md](SEAWEEDFS-ENHANCED-DISK-SIMULATION.md); bare-metal когда доступен |

---

## 6. Ссылки на документы

| Документ | Назначение |
|----------|------------|
| [TZ-ACCEPTANCE-MATRIX.md](TZ-ACCEPTANCE-MATRIX.md) | Матрица приёмки §4–§8 |
| [SNAPSHOT-BUCKET-MIGRATION-RUNBOOK.md](SNAPSHOT-BUCKET-MIGRATION-RUNBOOK.md) | vab→csb migration (без apply) |
| [VMALERT-INTEGRATION.md](VMALERT-INTEGRATION.md) | vmalert + VictoriaMetrics |
| [CUSTOMER-INCIDENT-DIAGNOSTICS.md](CUSTOMER-INCIDENT-DIAGNOSTICS.md) | Incident bundle script |
| [SEAWEEDFS-DISK-SIM-E2E.md](SEAWEEDFS-DISK-SIM-E2E.md) | E2E disk-sim overlay (design) |
| [README-STAND.md](../README-STAND.md) | Быстрый старт, архитектура |
| [CASSANDRA-TASK-STATUS.md](CASSANDRA-TASK-STATUS.md) | Задача №2 §5 |
| [CASSANDRA-LOAD-MODEL.md](CASSANDRA-LOAD-MODEL.md) | Capacity model |
| [CASSANDRA-CUSTOMER-QUESTIONS.md](CASSANDRA-CUSTOMER-QUESTIONS.md) | Checklist к заказчику |
| [SEAWEEDFS-ENHANCED-DISK-SIMULATION.md](SEAWEEDFS-ENHANCED-DISK-SIMULATION.md) | Host loopback disk sim |
| [SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md](SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md) | Задача №1 bare-metal |
| [seaweedfs-disk-health.md](seaweedfs-disk-health.md) | Disk-health патч |
| [sideweed-health.md](sideweed-health.md) | Write gate |
| [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md) | Alerting §6.4 (metrics + sample rules) |
| [STAND-TESTING.md](STAND-TESTING.md) | Тесты stand |
| [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md) | Read-only audit prod configs |
| [TZ-DEVIATIONS.md](TZ-DEVIATIONS.md) | Stand vs production |

---

*Внутренний документ. Design Cassandra: [CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md).*
