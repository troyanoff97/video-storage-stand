# Сводка локального milestone (internal)

Краткая внутренняя сводка опубликованного milestone.  
**Не для заказчика.** Детали — в связанных документах.

---

## 1. Текущее состояние

| Параметр | Значение |
|----------|----------|
| **Root repo** | `origin/main` @ **`336b451`**, синхронизирован с remote |
| **sideweed submodule** | `origin/master` @ **`2a428d2`**, на remote |
| **SeaweedFS fork** | pin **`1528e7d`**, без изменений в этом milestone |
| **Push** | **Выполнен** (см. [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md)) |
| **Production config audit** | [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md) — read-only, 2026-06-25 |

---

## 2. Состав milestone

### Cassandra (задача №2, §5)

| Артефакт | Статус |
|----------|--------|
| Design оптимизации | [CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md) |
| `schema-v2.cql` (experimental, не runtime) | [CASSANDRA-SCHEMA-V2.md](CASSANDRA-SCHEMA-V2.md) |
| Snapshot csb PUT/GET smoke | `make test-snapshot` |
| Range-query smoke | `make test-range-query` |
| Load model | [CASSANDRA-LOAD-MODEL.md](CASSANDRA-LOAD-MODEL.md) |
| Чеклист вопросов заказчику | [CASSANDRA-CUSTOMER-QUESTIONS.md](CASSANDRA-CUSTOMER-QUESTIONS.md) |

Runtime `cassandra/schema.cql` и `docker-compose.yml` для v2 **не менялись**.

### SeaweedFS (задача №1, §4)

| Артефакт | Статус |
|----------|--------|
| План bare-metal disk tests | [SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md](SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md) — **прогон не выполнен** |
| Enhanced host disk sim | [SEAWEEDFS-ENHANCED-DISK-SIMULATION.md](SEAWEEDFS-ENHANCED-DISK-SIMULATION.md), `scripts/disk-sim/` |

### sideweed (задача №3, §6)

| Артефакт | Статус |
|----------|--------|
| Write gate | [sideweed-health.md](sideweed-health.md) |
| `GET /metrics`, `GET /v1/write-health` | sideweed **`2a428d2`** |
| Sample Prometheus scrape + alert rules | `observability/` |
| Alerting design | [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md) — **delivery не реализован** |

### Процесс

| Артефакт | Статус |
|----------|--------|
| Статус по ТЗ | [TZ-IMPLEMENTATION-STATUS.md](TZ-IMPLEMENTATION-STATUS.md) |
| Push checklist | [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md) |

---

## 3. Подтверждённые тесты

Fresh clone verification (`video-storage-stand-fresh-metrics`):

| Команда | Результат |
|---------|-----------|
| `make up` / `make health` | PASS |
| `make test` | PASS |
| `make test-snapshot` | PASS |
| `make test-range-query` | PASS |
| `make verify-path` | PASS |
| `make test-sideweed` | **PASS=30 FAIL=0** |
| `go test ./...` | PASS |
| `GET /v1/write-health` | PASS (`status: healthy`) |
| `GET /metrics` | PASS (`sideweed_write_health_status`) |

`make chaos-matrix` в этом прогоне **не запускался**.

---

## 4. Ограничения

- **Alertmanager delivery** не реализован — только metrics + sample rules.
- **Cassandra production DDL** не применялся — `schema-v2.cql` draft.
- **Bare-metal disk tests** — план есть; заказчик не предоставляет host; **enhanced local sim** (`scripts/disk-sim/`) — не заменяет sign-off.
- **Production rollout** не выполнен.
- **Direct per-volume probes** и **multi-master health** в sideweed не закрыты.

---

## 5. Следующие шаги

| Приоритет | Действие |
|-----------|----------|
| 1 | **Alerting delivery** — Alertmanager/webhook в prod stack |
| 2 | **Production audit** — vab→csb migration checklist, vmalert rules |
| 3 | **Cassandra prod data** — [CASSANDRA-CUSTOMER-QUESTIONS.md](CASSANDRA-CUSTOMER-QUESTIONS.md) |
| 4 | **SeaweedFS §4** — [SEAWEEDFS-ENHANCED-DISK-SIMULATION.md](SEAWEEDFS-ENHANCED-DISK-SIMULATION.md) локально; bare-metal при появлении host |

---

## 6. Ссылки

| Документ | Назначение |
|----------|------------|
| [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md) | Production configs audit |
| [TZ-IMPLEMENTATION-STATUS.md](TZ-IMPLEMENTATION-STATUS.md) | Полный статус по ТЗ |
| [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md) | Push и fresh-clone |
| [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md) | Metrics и sample rules |
| [CASSANDRA-TASK-STATUS.md](CASSANDRA-TASK-STATUS.md) | Задача №2 Cassandra |

---

*Внутренний снимок. Обновлять при смене verified baseline.*
