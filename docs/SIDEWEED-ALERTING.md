# sideweed alerting — design proposal (ТЗ §6.4)

Предложение по **доставке алертов** для write gate sideweed.  
**Не production implementation** — только design для согласования с monitoring stack заказчика.

**Связанные документы:**

- [sideweed-health.md](sideweed-health.md) — write gate, логи, probes
- [STAND-TESTING.md](STAND-TESTING.md) — `make test-sideweed`
- [TZ-IMPLEMENTATION-STATUS.md](TZ-IMPLEMENTATION-STATUS.md) — сводный статус ТЗ

---

## 1. Purpose

### Зачем alerting

Write sideweed уже **блокирует** запись при деградации SeaweedFS (503 fail-fast). Операторам нужно **проактивное уведомление**, когда:

- write path degraded дольше порога;
- PUT массово отклоняются;
- backend'ы недоступны;
- состояние **флапает** (нестабильный кластер).

Без alerting инцидент виден только по жалобам клиентов или ручному разбору логов.

### Пункты ТЗ

| ТЗ | Статус сейчас | Роль этого документа |
|----|---------------|---------------------|
| **6.4 Logging** | **Done** (structured JSON) | События → источник для metrics/alerts |
| **6.4 Alerting** | **Not done** | Proposal metrics + rules + delivery |

### Что уже есть

| Компонент | Есть |
|-----------|------|
| Structured logs (`-l --json`) | `WRITE_DEGRADED`, `PUT_BLOCKED`, `WRITE_RECOVERED` |
| `reason` в логах | `master_down`, `assign_failed`, `all_volumes_down`, `s3_down`, `filer_down`, `s3_backend_down`, `write_health_degraded` |
| Integration test | `make test-sideweed` PASS (12+/12) |
| Fail-fast PUT | 503 &lt;1s при деградации |
| **Phase 1 metrics** | `GET /metrics` на write sideweed (локально в fork, commit `7eadd37`) |
| **Phase 2 sample configs** | `observability/prometheus-sideweed.yml`, `observability/sideweed-alert-rules.yml` |

### Что не реализовано

- Alertmanager / webhook **delivery** (Slack, PagerDuty, etc.)
- Grafana dashboards для write gate
- Production monitoring stack integration (compose profile не подключён)

---

## 2. Current state

| Поведение | Подтверждение |
|-----------|---------------|
| Write health probes (S3, filer, master, assign) | [sideweed-health.md](sideweed-health.md) |
| PUT blocked 503 при master/volumes/S3 down | `make test-sideweed` |
| Recovery → `WRITE_RECOVERED`, PUT 200 | `make test-sideweed` recovery scenarios |
| Read path не блокируется write gate | `sideweed-read` + chaos matrix #7 |
| **Prometheus `/metrics`** | `curl http://localhost:8880/metrics`, `make test-sideweed` |
| **Sample scrape + alert rules** | [observability/prometheus-sideweed.yml](../observability/prometheus-sideweed.yml), [observability/sideweed-alert-rules.yml](../observability/sideweed-alert-rules.yml) |
| Alert delivery | **Отсутствует** — только `docker logs` / journal / scrape metrics |

**Gap ТЗ 6.4:** logging ✓, metrics endpoint ✓ (локально), sample rules ✓, alert **delivery** ✗.

---

## 3. Alert events

События для мониторинга (из логов и будущих metrics).

| Event | Источник | Когда срабатывает | Alert candidate |
|-------|----------|-------------------|-----------------|
| **WRITE_DEGRADED** | Health probe loop | Любой probe fail → state `degraded` | Warning/Critical по duration |
| **PUT_BLOCKED** | Request middleware | PUT/POST/DELETE при degraded или S3 backend down | Rate-based warning |
| **WRITE_RECOVERED** | Health probe loop | `recoveryThreshold` успешных раундов | Info / resolve previous alert |
| **Backend / S3 down** | Backend health callback | S3 site offline | Critical |
| **Master down** | Probe `master` / `assign` | `reason=master_down` / `assign_failed` | Critical |
| **All volumes down** | Probe `assign` | `reason=all_volumes_down` | Critical |
| **Repeated PUT_BLOCKED** | Counter rate | N блокировок за 1–5 min | Warning |
| **Degraded &gt; N seconds** | Gauge `write_health_status==0` | Непрерывная деградация | Warning → Critical по SLA |
| **Flapping** | State changes / counter | ≥K degraded/recovered за window W | Warning (instability) |

### Reason → operational meaning

| reason | Вероятная причина | Suggested action |
|--------|-------------------|------------------|
| `master_down` | Master недоступен | Проверить master pod/VM, сеть |
| `assign_failed` / `all_volumes_down` | Нет writable volumes | Volume nodes, disk health |
| `s3_down` | S3 Gateway | s3 process, filer dependency |
| `filer_down` | Filer | filer logs, Cassandra/meta backend |
| `s3_backend_down` | Sideweed backend pool | Upstream S3 endpoints |
| `write_health_degraded` | Aggregate (см. probe) | Корреляция с SeaweedFS chaos |

---

## 4. Metrics (Prometheus) — Phase 1 implemented

Префикс: `sideweed_`. Exporter: **встроенный** `GET /metrics` на write sideweed (также legacy `/.prometheus/metrics`).

**Статус:** реализовано локально в fork sideweed (`7eadd37`). Sample alert rules — [observability/sideweed-alert-rules.yml](../observability/sideweed-alert-rules.yml); **не применены** на stand runtime.

| Metric | Type | Labels | Описание | Cardinality notes |
|--------|------|--------|----------|-------------------|
| `sideweed_write_health_status` | **Gauge** | — | 1=healthy, 0=degraded | Low |
| `sideweed_put_blocked_total` | **Counter** | `reason` | Заблокированные мутирующие запросы | Low — `s3_backend_down`, `write_health_degraded` |
| `sideweed_write_degraded_total` | **Counter** | `reason` | Переходы в degraded | Low — bounded reason enum |
| `sideweed_write_recovered_total` | **Counter** | — | Переходы в recovered | Very low |
| `sideweed_backend_up` | **Gauge** | `backend` | 1=UP per S3 backend (host из endpoint) | Low — stable backend host |
| `sideweed_health_probe_duration_seconds` | **Histogram** | `probe` | Latency probe (s3, filer, master, assign) | Low — probe names from config |

**Также (upstream):** `sideweed_requests_total`, `sideweed_errors_total`, `sideweed_rx_bytes_total`, `sideweed_tx_bytes_total` per endpoint.

### Proposal (not implemented)

| Metric | Type | Labels | Описание |
|--------|------|--------|----------|
| `sideweed_health_probe_success` | **Gauge** | `probe` | Last probe 1/0 |
| `sideweed_put_block_duration_seconds` | **Histogram** | — | Time to return 503 (fail-fast) |
| `sideweed_http_requests_total` | **Counter** | `method`, `code`, `blocked` | Optional generic request counter |

**Не использовать как label:** полный S3 object path, `camera_id`, client IP (cardinality explosion).

**Read sideweed:** отдельный `instance` или `role=read`; write gate metrics только на write instance.

---

## 5. Alert rules — Phase 2 sample configs

**Файлы (reference, не runtime):**

| Файл | Назначение |
|------|------------|
| [observability/prometheus-sideweed.yml](../observability/prometheus-sideweed.yml) | Scrape `sideweed:8880/metrics`, `rule_files` |
| [observability/sideweed-alert-rules.yml](../observability/sideweed-alert-rules.yml) | Prometheus alert rules (7 alerts) |

Проверка: `promtool check config observability/prometheus-sideweed.yml` и `promtool check rules observability/sideweed-alert-rules.yml`.

**Не подключено** к `docker-compose.yml`. Пороги — стартовые, tune на prod.

### Implemented alert names

| Alert | Severity (default) | Краткое условие |
|-------|-------------------|-----------------|
| `SideweedWriteHealthDegraded` | warning | `write_health_status == 0` for 30s |
| `SideweedPutBlocked` | warning | any `put_blocked_total` increase in 5m |
| `SideweedPutBlockedHighRate` | warning | block rate > 0.5/s for 5m |
| `SideweedBackendDown` | critical | `backend_up == 0` for 1m |
| `SideweedWriteHealthFlapping` | warning | >6 status changes in 15m |
| `SideweedNoRecoveryAfterDegradation` | critical | degraded 30m, no recovery counter |
| `SideweedHealthProbeSlow` | warning | probe p95 > 2s for 5m |

### Design notes (§5 legacy proposal)

| | |
|---|---|
| **Condition** | `sideweed_write_health_status == 0` for **30s** |
| **Severity** | **warning** (30s–5m), **critical** (&gt;5m) |
| **Description** | Write sideweed degraded — PUT blocked |
| **Action** | `make test-sideweed` equivalent checks; SeaweedFS master/volumes/S3 |

### PutBlockedRateHigh

| | |
|---|---|
| **Condition** | `rate(sideweed_put_blocked_total[5m]) > 10` (tune) |
| **Severity** | warning |
| **Description** | High rate of blocked writes |
| **Action** | Correlate with `reason` label; check client retry storms |

### AllBackendsDown

| | |
|---|---|
| **Condition** | `sum(sideweed_backend_up) == 0` |
| **Severity** | critical |
| **Description** | No S3 backends UP for sideweed |
| **Action** | S3 GW fleet, LB config |

### S3BackendDown

| | |
|---|---|
| **Condition** | `sideweed_backend_up{backend="s3"} == 0` for 1m |
| **Severity** | critical |
| **Description** | S3 backend marked down |
| **Action** | s3 container/process, filer |

### MasterDown

| | |
|---|---|
| **Condition** | `sideweed_health_probe_success{probe="master"} == 0` for 30s |
| **Severity** | critical |
| **Description** | Master probe failing |
| **Action** | master health, cluster status |

### WriteHealthFlapping

| | |
|---|---|
| **Condition** | `changes(sideweed_write_health_status[15m]) > 6` |
| **Severity** | warning |
| **Description** | Write health flapping |
| **Action** | Unstable network, probe timeout too aggressive, disk faults |

### NoRecoveryAfterDegradation

| | |
|---|---|
| **Condition** | `sideweed_write_health_status == 0` and `increase(sideweed_write_recovered_total[30m]) == 0` |
| **Severity** | critical |
| **Description** | Degraded &gt;30m without recovery event |
| **Action** | Manual intervention; chaos not self-healing |

### Example PromQL snippets

```yaml
# WriteHealthDegraded (warning)
- alert: SideweedWriteHealthDegraded
  expr: sideweed_write_health_status == 0
  for: 30s
  labels:
    severity: warning
  annotations:
    summary: "sideweed write path degraded"

# PutBlockedRateHigh
- alert: SideweedPutBlockedRateHigh
  expr: rate(sideweed_put_blocked_total[5m]) > 10
  for: 2m
  labels:
    severity: warning
```

---

## 6. Delivery options

| Вариант | Плюсы | Минусы | Когда выбирать |
|---------|-------|--------|----------------|
| **Prometheus + Alertmanager** | Стандарт, routing, silences | Нужен Prometheus stack | Customer already has Prometheus |
| **Webhook** (generic HTTP) | Простая интеграция | Нет встроенного routing | Custom incident system |
| **Slack / Telegram** | Быстрый ops channel | Не on-call grade alone | Dev stand, secondary notify |
| **Customer monitoring** (Zabbix, Datadog, etc.) | Единая панель заказчика | Mapping metrics → их модель | **Финальный prod path** |

**Зависимость:** финальная интеграция **только после** согласования production monitoring stack с заказчиком (как [CASSANDRA-CUSTOMER-QUESTIONS.md](CASSANDRA-CUSTOMER-QUESTIONS.md) для Cassandra).

**Stand proposal:** optional compose profile `prometheus` + `alertmanager` — не в default `make up`.

---

## 7. Stand-level implementation plan (proposal only)

### Phase 1 — Metrics in sideweed fork

- Добавить `/metrics` (Prometheus client_golang)
- Инкремент counters при `WRITE_DEGRADED`, `PUT_BLOCKED`, `WRITE_RECOVERED`
- Gauge `write_health_status` sync с state machine
- Unit tests: mock degraded → metric values
- **Не менять** fail-fast semantics

### Phase 2 — Stand observability profile

- ~~`prometheus/rules/sideweed.yml`~~ → **`observability/sideweed-alert-rules.yml`** (sample, not in compose)
- **`observability/prometheus-sideweed.yml`** — scrape config sample
- `docs/` update: paths and promtool validation
- Grafana dashboard draft (optional, not done)

### Phase 3 — Customer integration

- Согласовать metric names / labels с SRE заказчика
- Deploy rules в prod Alertmanager
- Runbook links в alert annotations
- Soak test + game day

**Текущий статус:** Phase 1 metrics ✓, Phase 2 sample configs ✓, delivery / compose profile — pending.

---

## 8. Test plan (proposal)

| Step | Действие | PASS |
|------|----------|------|
| T1 | Baseline: `curl sideweed:8880/metrics` → `write_health_status 1` | 200 + gauge |
| T2 | `make test-sideweed` unchanged PASS | 12/12 |
| T3 | master down → `put_blocked_total` increases, gauge 0 | After Phase 1 |
| T4 | recovery → `write_recovered_total` increases, gauge 1 | After Phase 1 |
| T5 | `promtool check rules observability/sideweed-alert-rules.yml` | Valid YAML/rules |
| T6 | Optional: amtool test alert fires on recorded metrics | Phase 2 |

Расширение `make test-sideweed`: optional `--metrics` flag или sub-step после chaos — **отдельный commit**, не в этом proposal.

---

## 9. Mapping to ТЗ

| Пункт | Current status | Proposal / next | Blockers |
|-------|----------------|-----------------|----------|
| **6.4 Logging** | **Done** | Keep JSON events; optional log shipping (Loki) | — |
| **6.4 Alerting** | **Partial** | Phase 1 metrics + Phase 2 sample Prometheus/alert rules | [observability/](../observability/), [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md) | Alertmanager delivery, prod stack wiring | Customer monitoring stack |
| **6.1–6.3** | **Done** | Metrics mirror existing behavior | — |

Обновление сводного статуса: [TZ-IMPLEMENTATION-STATUS.md](TZ-IMPLEMENTATION-STATUS.md) — §6.4 alerting = **partial** (metrics + sample rules; delivery pending).

---

## 10. Open questions for customer / SRE

1. Есть ли Prometheus/Alertmanager в production? Версии?
2. Кто владелец on-call для write path (sideweed vs SeaweedFS vs S3)?
3. Пороги: допустимое время degraded (SLA) до page?
4. Нужны ли алерты на **read** sideweed отдельно?
5. Retention metrics и cardinality budget?

---

*Proposal для Задачи №3 §6.4. Runtime sideweed/stand не изменён.*
