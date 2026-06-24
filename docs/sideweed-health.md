# Write gate sideweed при деградации

Production **write** sideweed (`:8880`) блокирует мутирующие запросы при нездоровом write path SeaweedFS, не проксируя PUT в S3 Gateway.

**Read** sideweed (`sideweed-read` за HAProxy) без изменений — write gate отсутствует.

Fork для push: [github.com/troyanoff97/sideweed](https://github.com/troyanoff97/sideweed).  
Upstream (read-only): [github.com/targetaidev/sideweed](https://github.com/targetaidev/sideweed).

## Архитектура

```
PUT/POST/DELETE → sideweed:8880
  ├─ нет UP S3 backend           → 503 PUT_BLOCKED reason=s3_backend_down (immediate)
  ├─ write health degraded      → 503 PUT_BLOCKED reason=write_health_degraded (immediate)
  └─ write health OK            → proxy → S3:8333 → filer → master → volumes

GET/HEAD → sideweed:8880 (если используется) или HAProxy:8882 → sideweed-read → S3
  └─ не блокируется write gate (502 только если S3 backend полностью DOWN)
```

## 502 vs 503

| Status | Источник | Когда |
|--------|----------|-------|
| **503** | Write gate | PUT/POST/DELETE при известной деградации write path или отсутствии S3 backend для записи |
| **502** | LB proxy layer | GET (или запросы без write gate) когда все S3 backend'ы DOWN |

**Ожидание production:** деградировавший write cluster → PUT всегда **503 fail-fast**, никогда 502.

Write gate выполняется **до** выбора backend proxy для мутирующих методов, поэтому S3 backend DOWN на PUT даёт **503** (не 502).

## Write health probes

Включаются флагом `--write-health-enabled` и повторяемым `--write-health-check=name=url[|code]`.

Стенд (write sideweed):

| Probe | URL | Expected |
|-------|-----|----------|
| s3 | `http://s3:8333/healthz` | 200 |
| filer | `http://filer:8888/` | 200 |
| master | `http://master:9333/cluster/status` | 200 |
| assign | `http://master:9333/dir/assign?count=1&replication=000` | 200 |

Probes выполняются **параллельно** с коротким timeout (по умолчанию 1s). **Первый неуспешный раунд** → `WRITE_DEGRADED` (без ожидания 2 раундов).

## Машина состояний

| Состояние | Значение |
|-----------|----------|
| `degraded` | Начальное / после failed probes или S3 backend offline |
| `healthy` | После `recoveryThreshold` последовательных успешных раундов probes |

События в логе (с `-l --json`):

| Status | Поле reason | Значение |
|--------|-------------|----------|
| `WRITE_DEGRADED` | `master_down`, `assign_failed`, `all_volumes_down`, `s3_down`, `filer_down` | Write path нездоров |
| `WRITE_RECOVERED` | — | Write path снова здоров |
| `PUT_BLOCKED` | `s3_backend_down` или `write_health_degraded` | Отклонён мутирующий запрос |

## Флаги конфигурации

| Флаг | По умолчанию | Описание |
|------|--------------|----------|
| `--write-health-enabled` | off | Включить write gate |
| `--write-health-interval` | `health-duration` | Интервал probes |
| `--write-unhealthy-threshold` | 1 | Неуспешных раундов до WRITE_DEGRADED (1 = сразу при первом сбое) |
| `--write-recovery-threshold` | 2 | Успешных раундов до WRITE_RECOVERED |
| `--put-block-status` | 503 | Status для заблокированных записей |
| `--upstream-timeout` | 30s | Dial timeout proxy (не влияет на блок PUT при known-degraded) |
| `--write-health-timeout` | 1s | Timeout одного probe |

## Блокируемые методы

`PUT`, `POST`, `DELETE` при write state `degraded` или S3 backend DOWN.

`GET`, `HEAD` проксируются нормально, если S3 upstream UP; иначе 502.

## Prometheus metrics

Write sideweed экспортирует Prometheus metrics на:

- `GET /metrics` (основной endpoint)
- `GET /.prometheus/metrics` (legacy, тот же handler)

## Health endpoints

| Endpoint | Назначение | HTTP при OK | HTTP при проблеме |
|----------|------------|-------------|------------------|
| `GET /v1/health` | **LB / backend pool** — есть ли UP S3 backend для proxy | 200 (пустое тело) | 502 |
| `GET /v1/write-health` | **Write gate readiness** — aggregate write path + per-probe JSON | 200 + `status: healthy` | 503 + `status: degraded` |

`/v1/health` **не** отражает write gate: при master down и живом S3 backend `/v1/health` может оставаться **200**, тогда как `/v1/write-health` → **503**.

`GET /v1/write-health` возвращает JSON:

- `status`: `healthy` | `degraded` | `disabled` (если `--write-health-enabled` off)
- `healthy`: boolean
- `reason`: bounded degraded reason (`master_down`, `assign_failed`, …) или `""`
- `updated_at`: RFC3339 последнего probe round
- `probes[]`: `name`, `url`, `ok`, `status_code`, `latency_ms`, `error`, `checked_at`

Пример:

```bash
curl -fsS http://localhost:8880/v1/write-health | jq .
```

При отключённом write gate: **200** + `{"status":"disabled","healthy":true}`.

Пример metrics:

```bash
curl -fsS http://localhost:8880/metrics | grep sideweed_write_health_status
```

Ключевые метрики write gate: `sideweed_write_health_status`, `sideweed_write_degraded_total{reason}`, `sideweed_write_recovered_total`, `sideweed_put_blocked_total{reason}`, `sideweed_backend_up{backend}`, `sideweed_health_probe_duration_seconds`.

Подробнее: [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md) (Phase 1 implemented; Alertmanager rules — proposal).

## Aggregate write readiness (volume nodes)

Sideweed оценивает **возможность записи на кластер в целом**, а не health каждого volume node напрямую.

| Сигнал | Механизм |
|--------|----------|
| Writable capacity | Probe `assign` → `master /dir/assign` (HTTP 200 = есть writable volume) |
| All volumes lost | `assign` → 406 → `all_volumes_down` → PUT blocked |
| **Single volume down** | Если другой volume writable, `assign` остаётся **200** → write path **healthy**, PUT **не** блокируется |

На стенде (`replication=000`, volume1 + volume2): `compose stop volume1` при живом volume2 — **ожидаемо** `GET /v1/write-health` **200**, PUT **200**. Покрыто `make test-sideweed` (сценарий *single volume down*).

Direct per-volume `/healthz` probes **не** входят в production write sideweed (debug: `sideweed-volumes` profile).

## Тестирование

```bash
make test-sideweed    # integration: 503 <1s, reason logs, recovery
cd sideweed && go test -v ./...   # unit tests
```

## Ограничения (стенд)

- Write gate только на **write** sideweed, не на `sideweed-read`
- Здоровье volume выводится через master `/dir/assign`, не через per-volume `/status`
- S3 backend offline также вызывает `WRITE_DEGRADED reason=s3_down` через backend health callback
- Threshold/interval настроены под docker-стенд
- **Filer down** покрыт `make test-sideweed` (отдельный сценарий: `compose stop filer` → degraded → recovery)

См. [chaos-expectations.md](chaos-expectations.md), [STAND-TESTING.md](STAND-TESTING.md).
