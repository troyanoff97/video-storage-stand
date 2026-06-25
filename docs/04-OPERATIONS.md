# Operations

## sideweed endpoints (write instance)

| Endpoint | Use | HTTP |
|----------|-----|------|
| `GET /v1/write-health` | Write readiness + probes | 200 healthy / 503 degraded |
| `GET /v1/health` | LB backend pool | 200 / 502 |
| `GET /metrics` | Prometheus | 200 |

```bash
curl -fsS http://localhost:8880/v1/write-health | jq .
curl -fsS http://localhost:8880/metrics | grep '^sideweed_'
```

**Key metrics:** `sideweed_write_health_status`, `sideweed_put_blocked_total{reason}`, `sideweed_write_degraded_total{reason}`, `sideweed_backend_up`, `sideweed_health_probe_duration_seconds`.

**Log events (JSON):** `WRITE_DEGRADED`, `PUT_BLOCKED`, `WRITE_RECOVERED`.

### Probe → action

| reason | Likely cause | Action |
|--------|--------------|--------|
| `master_down` | master down | check quorum |
| `assign_failed` / `all_volumes_down` | no writable volume | volume nodes, disk health |
| `filer_down` / `s3_down` | gateway/filer | logs, Cassandra backend |
| `s3_backend_down` | sideweed pool empty | S3 endpoints |

Volume probes with `blocking: false` are **visibility only** — page ops, do not expect PUT block on single volume down.

## Alert rules (reference, not deployed)

Files: `observability/vmalert-sideweed-rules.yml`, `observability/sideweed-alert-rules.yml`, `observability/prometheus-sideweed.yml`.

| Alert | Condition (summary) |
|-------|---------------------|
| SideweedWriteHealthDegraded | `write_health_status==0` 30s |
| SideweedPutBlocked | increase 5m |
| SideweedBackendDown | `backend_up==0` 1m |
| SideweedNoRecoveryAfterDegradation | degraded 30m |

Validate: `python3 -c "import yaml; yaml.safe_load(open('observability/vmalert-sideweed-rules.yml'))"`

## VictoriaMetrics / vmalert

1. Scrape write sideweed `/metrics` (e.g. 15s, `role=write`)
2. Load `observability/vmalert-sideweed-rules.yml`
3. Wire notifier (customer-owned)
4. Dashboard: health status, put_blocked, probe latency

**Stand:** rules not wired in `docker-compose.yml`. **Production:** VM + Grafana + vmalert (not Alertmanager).

## Incident bundle (read-only)

```bash
export SIDEWEED_URL="http://127.0.0.1:9000"      # adjust for prod
export SEAWEED_MASTER_URL="http://127.0.0.1:9333"
bash scripts/customer/collect_seaweedfs_incident_bundle.sh
```

Collects: hostname, systemd status, journals, dmesg, mounts/df/lsblk, optional `/v1/write-health` and filtered `/metrics`. **No** restarts, config changes, or secrets.

Env: `INCIDENT_SINCE`, `INCIDENT_UNTIL`, `OUTPUT_DIR`.

## SeaweedFS volume (disk incidents)

- Logs: `marked unhealthy`, `disk health changed`, `recovered and is healthy again`
- `GET volume:/status` → `DiskHealth[]`
- Master removes unhealthy dirs from writables

## Gaps

| Phase | Status |
|-------|--------|
| Metrics in sideweed fork | **Done** |
| Sample rules in repo | **Done** |
| Customer vmalert deploy | **Blocked** |
| Grafana dashboards | **Not started** |

**Ask customer SRE:** scrape owner, on-call, degraded SLA, read-side alerts, retention.
