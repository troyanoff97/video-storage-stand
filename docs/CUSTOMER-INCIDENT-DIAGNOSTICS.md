# Диагностика инцидентов SeaweedFS / sideweed (заказчик)

Руководство по **безопасному** сбору данных при инциденте disk/volume/write path.

**Скрипт:** [scripts/customer/collect_seaweedfs_incident_bundle.sh](../scripts/customer/collect_seaweedfs_incident_bundle.sh)

---

## 1. Принципы безопасности

Скрипт **read-only**:

- не меняет конфиги;
- не рестартит сервисы;
- не удаляет файлы;
- не требует destructive actions.

Если команда недоступна — **warning** в лог, сбор продолжается.

**Конфиги с secrets** (streamserver, teye, cassandra, S3 keys) — **не** собираются по умолчанию.  
Отправлять **отдельно** с redacted secrets (пароли, tokens, access_key).

---

## 2. Что собирается

| Категория | Данные |
|-----------|--------|
| Host | hostname, date, uptime |
| systemd | status: weed-volume, weed-master, weed-filer, sideweed, haproxy, varnish, cassandra |
| journal | weed-volume (с фильтром времени при задании), weed-master, weed-filer |
| Kernel / disk | dmesg, mount, findmnt, df, lsblk |
| HTTP (optional) | sideweed `/v1/write-health`, `/metrics` (только `sideweed_*`) |
| HTTP (optional) | master `/cluster/status`, `/dir/assign?count=1&replication=000` |
| Output | `tar.gz` в `OUTPUT_DIR` |

---

## 3. Переменные окружения

| Variable | Описание |
|----------|----------|
| `INCIDENT_SINCE` | journalctl `--since` для weed-volume (напр. `2026-06-25 10:00`) |
| `INCIDENT_UNTIL` | journalctl `--until` для weed-volume |
| `SIDEWEED_URL` | Base URL write sideweed (напр. `http://127.0.0.1:9000`) |
| `SEAWEED_MASTER_URL` | Base URL master (напр. `http://127.0.0.1:9333`) |
| `OUTPUT_DIR` | Parent directory for collection (default: `/tmp`); files go to `OUTPUT_DIR/seaweedfs-incident-<UTC>/` |

---

## 4. Пример запуска

```bash
export INCIDENT_SINCE="2026-06-25 08:00"
export INCIDENT_UNTIL="2026-06-25 12:00"
export SIDEWEED_URL="http://127.0.0.1:9000"
export SEAWEED_MASTER_URL="http://127.0.0.1:9333"
export OUTPUT_DIR="/tmp/incident-001"

bash scripts/customer/collect_seaweedfs_incident_bundle.sh
# Результат: ${OUTPUT_DIR}/seaweedfs-incident-<UTC>.tar.gz (+ каталог с raw files)
```

На stand (docker, без systemd units):

```bash
export SIDEWEED_URL="http://localhost:8880"
export SEAWEED_MASTER_URL="http://localhost:9333"
bash scripts/customer/collect_seaweedfs_incident_bundle.sh
```

Ожидаются warnings для отсутствующих systemd units — это нормально.

---

## 5. Что отправить дополнительно (вручную)

- Redacted `streamserver.toml`, teye config, HAProxy/Varnish snippets
- `weed volume` unit files (без credentials)
- Grafana/vmalert alert history за период инцидента
- Результат `curl sideweed/v1/write-health` если скрипт не запускался

**Не отправлять:** plaintext passwords, S3 secret keys, JWT tokens.

---

## 6. Связь с ТЗ

| ТЗ | Coverage |
|----|----------|
| §4.4 logging | journal + dmesg для disk errors |
| §6.4 alerting | sideweed metrics snapshot |
| §7 testing | stand smoke с `SIDEWEED_URL` |

См. [TZ-ACCEPTANCE-MATRIX.md](TZ-ACCEPTANCE-MATRIX.md).

---

*Internal tooling. Не заменяет on-call runbook заказчика.*
