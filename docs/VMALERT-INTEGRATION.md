# Интеграция sideweed metrics с VictoriaMetrics / vmalert

Руководство по подключению write gate sideweed к **production monitoring stack заказчика**: VictoriaMetrics + Grafana + **vmalert**.

**Не production deployment** — reference configs для SRE.  
**Alertmanager** — optional/generic; **production target — vmalert**.

**Связанные файлы:**

- [observability/vmalert-sideweed-rules.yml](../observability/vmalert-sideweed-rules.yml)
- [observability/prometheus-sideweed.yml](../observability/prometheus-sideweed.yml) (scrape sample)
- [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md)
- [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md) §7

---

## 1. Совместимость

| Компонент | Формат |
|-----------|--------|
| sideweed `GET /metrics` | Prometheus text exposition |
| VictoriaMetrics scrape | **Совместим** (vmagent или vm single-node scrape) |
| vmalert rules | PromQL-подобные expressions (validate на стороне заказчика) |
| Grafana | Datasource → VictoriaMetrics |

---

## 2. Scrape target (пример)

Не использовать production URLs/secrets. Подставить host заказчика.

```yaml
# vmagent scrape_config fragment (example)
scrape_configs:
  - job_name: sideweed-write
    metrics_path: /metrics
    scrape_interval: 15s
    static_configs:
      - targets: ['<sideweed-write-host>:<port>']
        labels:
          role: write
          env: production
```

На stand (reference): `observability/prometheus-sideweed.yml` → `sideweed:8880/metrics`.

Дополнительно: `GET /v1/write-health` — для checks/dashboards, **не** заменяет metrics.

---

## 3. vmalert rule groups

Файл: `observability/vmalert-sideweed-rules.yml`

| Alert | Severity | Условие (кратко) |
|-------|----------|------------------|
| `SideweedWriteHealthDegraded` | warning | `write_health_status == 0` 30s |
| `SideweedPutBlocked` | warning | `increase(put_blocked_total[5m]) > 0` |
| `SideweedPutBlockedHighRate` | warning | block rate > 0.5/s |
| `SideweedBackendDown` | critical | `backend_up == 0` 1m |
| `SideweedWriteHealthFlapping` | warning | `changes(status[15m]) > 6` |
| `SideweedNoRecoveryAfterDegradation` | critical | degraded 30m, no recovery |
| `SideweedHealthProbeSlow` | warning | probe p95 > 2s |

Labels: `component=sideweed`, `subsystem=write-gate` (где применимо).  
Annotations: `summary`, `description`, `runbook` (пути к docs stand repo).

---

## 4. Deploy vmalert (outline)

1. Скопировать `vmalert-sideweed-rules.yml` на vmalert host.
2. Добавить в vmalert args: `-rule=vmalert-sideweed-rules.yml`, `-datasource.url=<victoriametrics-url>`.
3. Настроить notifier (Alertmanager, webhook, email) — **на стороне заказчика**.
4. `vmalert -dryRun -rule vmalert-sideweed-rules.yml` — syntax check.
5. Grafana dashboard: `sideweed_write_health_status`, `put_blocked_total`, `health_probe_duration_seconds`.

**Stand:** rules **не** подключены к `docker-compose.yml`.

---

## 5. Alertmanager (optional)

Для stand/dev можно использовать Prometheus + Alertmanager с [observability/sideweed-alert-rules.yml](../observability/sideweed-alert-rules.yml).  
В production заказчика приоритет — **vmalert**.

---

## 6. Проверка на stand

```bash
curl -fsS http://localhost:8880/metrics | grep sideweed_write_health_status
make test-sideweed   # 30/30, metrics checks included
```

---

*Reference only. Delivery на production — задача SRE заказчика.*
