# Аудит production-конфигов (read-only)

Внутренний аудит конфигураций заказчика из архивов **`stor1.tar.gz`** и **`teye.tar.gz`**.  
**Не для публикации.** Архивы **не коммитить** в git. Все секреты в этом документе — **`<redacted>`**.

**Источник:** `/home/cerf/Documents/ворк/` (локально, вне repo).  
**Дата аудита:** 2026-06-25.  
**Stand repo:** `origin/main` @ `45daa7b` (docs-only, без runtime changes).

---

## 1. Summary

| Область | Главный вывод |
|---------|---------------|
| **Архитектура** | Write: `streamserver` → `sideweed` → S3 Gateway (`:8333` на stor nodes) → filer/master/volumes. Read: `HAProxy` → (`Varnish` для snapshots) → S3 GW. |
| **Buckets** | **`vab`** — archive + camera snapshots (write). **`esb`** — event snapshots. **`csb`** — read path готов (HAProxy/Varnish), **write ещё не переведён**. **`vcb`**, **`vmb`** — videoclips/videomarks (teye). |
| **Cassandra** | SeaweedFS metadata: **`seaweedfs.filemeta`** (TWCS 6h, RF=3). **Не** stand `video_archive.fragments`. Application metadata teye — keyspace **`teye`** на отдельном DB-кластере. |
| **sideweed** | Primary `:9000` → `stor{1..3}:8333`; mirror `:9090` → `stor-mirror{1..3}:8333`. Балансирует S3 Gateway, не volume nodes. |
| **Monitoring** | У заказчика **VictoriaMetrics + Grafana + vmalert**. В архивах: Prometheus-format export (HAProxy `/metrics`, weed-master `-metrics.address`). Наши sideweed `/metrics` совместимы со scrape VictoriaMetrics. |
| **Disk fault** | Production `weed volume` — **14 `-dir`** (`/mnt/stor1`…`/mnt/stor14`). Подтверждает актуальность per-dir isolation. Bare-metal стенд заказчик **не предоставил**. |
| **Изменения не внесены** | Аудит read-only. Production configs **не менялись**. |

---

## 2. Полученные архивы

### stor1.tar.gz

Конфиги **storage node** (Cassandra + SeaweedFS на одном классе хостов `stor*`).

| Путь в архиве | Назначение |
|---------------|------------|
| `systemd/system/weed-volume.service` | Volume node: 14 data dirs, 3 master peers |
| `systemd/system/weed-filer.service` | Filer + S3 Gateway (`-s3`, port 8888/8333) |
| `systemd/system/weed-master.service` | 3-node master quorum, metrics export |
| `systemd/system/weed-filer.service.d/weed-filer-unit-config.conf` | Memory limits filer unit |
| `systemd/system/cassandra.service` | Cassandra на stor node |
| `seaweedfs/filer.toml` | Cassandra backend filer: keyspace `seaweedfs` |
| `cassandra/create_keyspaces.cql` | Keyspace `seaweedfs`, RF=3 |
| `cassandra/seaweedfs_tables.cql` | Table `filemeta` + TWCS |
| `cassandra/cassandra.yaml` | Cluster config (auth, seeds, compaction throughput) |
| `cassandra/*.cql`, `jvm-*`, `logback*` | Roles, grants, JVM — вспомогательные |

### teye.tar.gz

Конфиги **application tier**: streamserver, sideweed, HAProxy, Varnish, teye backend.

| Путь в архиве | Назначение |
|---------------|------------|
| `streamserver/config.toml` | S3 write endpoints, buckets, streamers |
| `sideweed/sideweed.environment` | Primary write LB |
| `sideweed/sideweed_mirror.environment` | Mirror write LB |
| `systemd/system/sideweed*.service` | Unit files |
| `haproxy/conf.d/*`, `haproxy/haproxy.cfg` | Frontend routing, storage backends |
| `haproxy/ticket.lua`, `cors.lua` | Ticket auth, CORS |
| `varnish/default.vcl` | Snapshot cache (esb/csb/vab jpeg) |
| `teye/config.toml` | Backend: storage URLs, snapshots, Cassandra `teye` keyspace |
| `systemd/system/streamserver.service` | streamserver unit |

**Секреты в архивах:** passwords, access_key/secret_key, ticket secrets, JWT keys — **не копировать в docs/repo**. Значения: `<redacted>`.

---

## 3. Production architecture

### Write path

```
streamserver
  → sideweed (primary :9000 / mirror :9090)
    → S3 Gateway stor{1..3}:8333  (weed filer -s3)
      → filer :8888
        → master quorum (3 nodes)
          → weed volume (-dir ×14 per stor node)
```

- **streamserver** пишет через S3 API на `sideweed` endpoint (`config.toml` `[s3]` / `[s3_mirror]`).
- **sideweed** (`SIDEWEED_SITES`) балансирует `http://stor{1..3}.node.<redacted>.teye:8333` — это **S3 Gateway**, не volume nodes.
- Archive chunks: `[[streamers.storage]].bucket_name = "vab"`.
- Camera snapshots (write): `[[streamers.snapshot]].bucket_name = "vab"` (**ещё не csb**).
- Event snapshots (VA): `[va].events_snapshot_bucket_name = "esb"`.

### Read path

```
Client (browser / teye API consumers)
  → HAProxy fe_lb (:443, public hostname)
    ├─ /s3/(esb|csb)/.*  OR  /s3/vab/.*\.jpeg  →  Varnish (:10000)  →  stor{1..3}:8333
    ├─ /s3/<mirror-uuid>/.*                     →  stor-mirror{1..3}:8333
    └─ /s3/* (остальное)                        →  be_teye_storage  →  stor{1..3}:8333 (без Varnish)
```

- Публичный base URL storage: `https://esvm.kz/s3` (teye `base_url`).
- Ticket verification (`lua.verify_ticket()`) на read path (кроме `/s3/upb/.*`).
- HAProxy strip `/s3/` prefix перед проксированием на S3 GW.

### sideweed endpoints (production)

| Instance | Listen | Backends (`SIDEWEED_SITES`) |
|----------|--------|----------------------------|
| Primary | `<host-ip>:9000` | `stor{1..3}.node.<redacted>.teye:8333` |
| Mirror | `<host-ip>:9090` | `stor-mirror{1..3}.node.<redacted>.teye:8333` |

Health: `--health-path /` на S3 backend. **Write-health gate** (`/v1/write-health`) в production env **не виден** — это enhancement в нашем fork.

### S3 Gateway endpoints

| Уровень | Endpoint |
|---------|----------|
| На stor node | `weed filer -s3 -port=8888 -s3.port=8333` |
| Через sideweed (write) | `:9000` / `:9090` |
| Через HAProxy (read) | `https://esvm.kz/s3/...` → backend `:8333` |
| teye internal | `http://<lb-ip>:9000` (storage discovery port 8333) |

### HAProxy / Varnish role

| Компонент | Роль |
|-----------|------|
| **HAProxy** | TLS termination, routing, ticket auth, CORS, `/live/` `/hls/` `/ptz/` к streamserver |
| **Varnish** | **Только** snapshot-like GET: `esb`, `csb`, `vab/*.jpeg`, `upb`; cache TTL по bucket |
| **sideweed** | **Только write path** (streamserver → S3 GW), не участвует в browser read |

---

## 4. Buckets and snapshot pipeline

| Bucket | Write (сейчас) | Read (сейчас) | Назначение |
|--------|----------------|---------------|------------|
| **vab** | streamserver storage + snapshot streamer; teye `videoarchives` | HAProxy → storage backend; Varnish для `vab/*.jpeg` | Video archive blobs + **camera snapshots** |
| **csb** | **не используется** для write | HAProxy → Varnish (`TTL 3s`) | Camera snapshots (**целевой** bucket по ТЗ) |
| **esb** | streamserver VA events; teye `storage.snapshots` | HAProxy → Varnish (`TTL 30d`) | **Event snapshots** |
| **vcb** | teye videoclips | HAProxy `/s3/` → storage | Video clips |
| **vmb** | teye videomarks | HAProxy `/s3/` → storage | Video marks |
| **upb** | (не детализировано в архиве) | Varnish `TTL 30m`; ticket bypass | User/profile blobs? |

### Camera snapshots (сейчас → цель csb)

| Слой | Сейчас | Для перевода в csb |
|------|--------|-------------------|
| streamserver `[[streamers.snapshot]].bucket_name` | `vab` | → `csb` |
| teye `[snapshots].camera_base_url` | `https://esvm.kz/s3/vab` | → `https://esvm.kz/s3/csb` |
| Varnish | `^/csb/` уже есть (`TTL 3s`) | без изменений |
| HAProxy ACL | `^/s3/(esb\|csb)/` → Varnish | без изменений |
| sideweed | bucket-agnostic | без изменений |
| Legacy read | `vab/*.jpeg` в Varnish (`TTL 30s`) | dual-read период; затем deprecate |

### Event snapshots

- Write: `streamserver` → `[va].events_snapshot_bucket_name = "esb"`.
- Read: teye `[snapshots].event_base_url = "https://esvm.kz/s3/esb"`.
- Varnish: `esb` TTL 30d.

**Миграция vab→csb для camera snapshots не выполнена** — только подготовлен read path.

---

## 5. Cassandra / SeaweedFS metadata

### SeaweedFS filer metadata (production)

Источник: `cassandra/create_keyspaces.cql`, `cassandra/seaweedfs_tables.cql`, `seaweedfs/filer.toml`.

| Параметр | Значение |
|----------|----------|
| Keyspace | `seaweedfs` |
| Replication | `SimpleStrategy`, **RF=3** |
| Table | **`filemeta`** |
| PK | `(directory, name)` |
| Compaction | **TWCS**: window **6 HOURS**, `gc_grace_seconds=3600`, tombstone compaction enabled |
| Filer config | `keyspace = "seaweedfs"`, hosts `stor{1..3}.node.<redacted>.teye:9042` |

**Это не stand `video_archive.fragments`.** Stand schema — тестовый клиентский индекс; production metadata пишет **SeaweedFS filer** в `seaweedfs.filemeta`.

### teye application Cassandra

Источник: `teye/config.toml` `[cassandra]`.

| Параметр | Значение |
|----------|----------|
| Keyspace | `teye` |
| Hosts | `db{1..3}.node.<redacted>.teye` (отдельный кластер от stor) |
| DDL в архиве | **не включён** |

### Вывод для stand docs

- Production DDL для **SeaweedFS metadata частично получен** (`filemeta` + TWCS).
- Оптимизация **application** metadata (camera fragments index, `time_bucket`, §5.3–5.4) — **отдельная задача**; teye DDL и query patterns **ещё не получены**.
- Stand `schema-v2.cql` остаётся experimental draft для **application** layer, не замена `seaweedfs.filemeta`.

### cassandra.yaml (stor cluster) — заметки

- `cluster_name: seaweedfscassandra`
- `authenticator: PasswordAuthenticator`, `authorizer: CassandraAuthorizer`
- `allocate_tokens_for_local_replication_factor: 3`
- `compaction_throughput: 64MiB/s`
- Seeds: stor1–stor3 nodes

---

## 6. sideweed / HAProxy / Varnish

### Production vs stand

| Аспект | Production | Stand |
|--------|------------|-------|
| sideweed role | S3 GW load balancer (write) | Write entry + optional read instance |
| Write-health gate | Не в env files архива | `--write-health-enabled`, `/v1/write-health` |
| HAProxy | Full prod routing + Varnish fork | Simplified read proxy `:8882` |
| Varnish | Snapshot cache layer | **Отсутствует** |
| Master count | 3 peers | 1 master |
| Volume dirs | 14 per node | 2 nodes × 1 dir |

### HAProxy storage backend

`be_teye_storage` → `stor{1..3}:8333` direct (leastconn).  
Path rewrite: strip `/s3/` и optional videoarchive UUID prefix.

### Varnish snapshot caching

| Path pattern | TTL |
|--------------|-----|
| `/esb/` | 30d |
| `/csb/` | 3s |
| `/vab/.*\.jpeg` | 30s |
| `/upb/` | 30m |

Round-robin director на stor1–stor3 `:8333`.

---

## 7. Monitoring: VictoriaMetrics / Grafana / vmalert

### Стек заказчика (известно по проекту)

- **VictoriaMetrics** — хранение metrics
- **Grafana** — dashboards
- **vmalert** — alerting rules

В архивах прямых конфигов VictoriaMetrics **нет**; есть scrape targets в формате Prometheus.

### Найдено в архивах

| Источник | Endpoint / механизм |
|----------|---------------------|
| `weed-master.service` | `-metrics.address=<lb-ip>:9091`, `-metricsPort=9095` |
| HAProxy `00-default.cfg` | `listen stats` `:7500`, `prometheus-exporter` на `/metrics` |
| streamserver `[mon]` | host/port metrics (отдельный mon endpoint) |

### Совместимость с нашим sideweed fork

- `GET /metrics` на write sideweed — **Prometheus text format**.
- VictoriaMetrics / vmagent **принимают** тот же scrape format, что Prometheus.
- Sample rules в `observability/sideweed-alert-rules.yml` — **PromQL**; для production target — **конвертация/адаптация под vmalert** (синтаксис близкий, но validate на стороне заказчика).
- **Alertmanager** — generic option для stand; **production target — vmalert**.

**Delivery alerting для sideweed write gate в production — не реализован** (ни в stand, ни у заказчика по этим архивам).

---

## 8. Disk fault implications

### Production facts

Из `weed-volume.service`:

```
-dir=/mnt/stor1,/mnt/stor2,...,/mnt/stor14
-minFreeSpace=50GiB
-mserver=<3 master peers>
```

- **14 отдельных mount points** на volume node → патч **per-dir unhealthy isolation** напрямую релевантен production.
- 3 stor nodes × 14 dirs = высокая cardinality disk paths.
- Bare-metal test host от заказчика **не предоставлен**.

### Enhanced local simulation (предложение)

Пока нет customer metal — усилить stand simulation (docs/runbook only, **не реализовано**):

| Техника | Что даёт | Ограничение |
|---------|----------|-------------|
| Loopback **ext4** images (`dd` + `mkfs.ext4` + `mount`) | Реальный FS, `fallocate`, `remount ro` | Не SMART, не RAID |
| **read-only remount** на одном `-dir` | Сценарий 4.2/4.3 partial | Не production latency |
| **disk full** (`fallocate` / `dd`) | minFreeSpace / readonly transition | tmpfs ведёт себя иначе |
| **dmsetup** error injection (optional) | I/O errors | Требует root, не везде доступно |

**Честно:** enhanced simulation **не заменяет** production bare-metal sign-off.

---

## 9. Что можно сделать без заказчика

| # | Действие |
|---|----------|
| 1 | Обновить stand docs с production facts (этот документ) |
| 2 | Сверить stand `observability/` rules с VictoriaMetrics/vmalert target |
| 3 | Подготовить migration checklist vab→csb (config keys выше) — **без apply** |
| 4 | Сравнить production `seaweedfs.filemeta` TWCS с stand `schema-v2` draft |
| 5 | Расширить disk-fault runbook: loopback ext4 simulation plan |
| 6 | Добавить vmalert-oriented sample в `observability/` (optional, отдельный commit) |
| 7 | Продолжить stand tests: `make test-sideweed`, chaos-matrix |

---

## 10. Что всё ещё требует заказчика

| # | Нужно от заказчика |
|---|-------------------|
| 1 | **Bare-metal** volume node для disk fault sign-off (§4) |
| 2 | **teye** Cassandra DDL + query patterns (application metadata §5.3–5.4) |
| 3 | Согласование и **apply** vab→csb migration (streamserver + teye + data backfill) |
| 4 | VictoriaMetrics scrape config для sideweed `/metrics` + vmalert rules deploy |
| 5 | Production rollout sideweed fork (`/v1/write-health`, write gate) — change window |
| 6 | `tablestats` / compaction tuning на `seaweedfs.filemeta` при росте данных |
| 7 | Dual-read period plan для legacy `vab/*.jpeg` URLs |

---

## 11. Риски и handling секретов

| Риск | Mitigation |
|------|------------|
| Архивы содержат **реальные secrets** | **Не коммитить** `stor1.tar.gz` / `teye.tar.gz`; хранить вне git |
| Утечка в docs | Все passwords/keys/tokens → `<redacted>`; не копировать `filer.toml` password в repo |
| TICKET_SECRET в HAProxy lua env | Не включать в docs |
| Неверные выводы из одного stor node | Архив stor1 — exemplar; другие nodes могут отличаться |
| csb «готов» ≠ «используется» | Read path есть; write migration **не сделана** |
| TWCS на `filemeta` ≠ полная оптимизация §5 | Application metadata teye — отдельный scope |

---

## Ссылки

- [TZ-IMPLEMENTATION-STATUS.md](TZ-IMPLEMENTATION-STATUS.md)
- [CASSANDRA-TASK-STATUS.md](CASSANDRA-TASK-STATUS.md)
- [CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md)
- [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md)
- [SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md](SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md)
- [TZ-DEVIATIONS.md](TZ-DEVIATIONS.md)

*Read-only audit. Production не изменялся.*
