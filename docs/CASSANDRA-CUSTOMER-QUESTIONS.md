# Cassandra optimization — внутренний checklist вопросов к заказчику

**Назначение:** технический список данных, которые нужны для production-level оптимизации Cassandra по ТЗ §5.  
**Это не письмо заказчику** — внутренний рабочий документ stand repo.

**Связанные документы:**

- [CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md) — design proposal
- [CASSANDRA-LOAD-MODEL.md](CASSANDRA-LOAD-MODEL.md) — расчётная модель нагрузки
- [CASSANDRA-TASK-STATUS.md](CASSANDRA-TASK-STATUS.md) — текущий статус Задачи №2

---

## 1. Назначение

### Зачем нужен checklist

Без фактических production данных нельзя безопасно:

- выбрать `time_bucket` (day / week / month) и PK для archive/snapshots;
- настроить TWCS windows, TTL, `gc_grace_seconds`;
- спланировать migration и backward compatibility (ТЗ §5.4);
- подтвердить, что stand proposal (`schema-v2.cql`, smoke tests) совместим с реальным pipeline.

[Load model](CASSANDRA-LOAD-MODEL.md) даёт **оценку порядка величин** (47.3B fragment rows / 3y / 10k cam; ~4.73M rows/partition при PK=`camera_id`), но не заменяет production metrics.

### Что нельзя закрыть без ответов

| ТЗ | Блокер без данных заказчика |
|----|----------------------------|
| **§5.3** compaction / search | Реальные query windows, row/SSTable sizes, compaction stats, tombstones |
| **§5.4** backward compatibility | Объём legacy data, dual-read policy, downtime SLA, rollback |

### Статус stand

Текущие изменения в repo — **proposal / prototype**:

- runtime: `cassandra/schema.cql` → `fragments`;
- `schema-v2.cql` не подключён;
- smoke: `make test-snapshot`, `make test-range-query`;
- design + load model — для обсуждения после получения ответов ниже.

---

## 2. Short version — top 10

1. **Production Cassandra DDL** — полный вывод `DESCRIBE` keyspaces/tables (PK, clustering, compaction, TTL, compression).
2. **Реальные query patterns** — point vs range; типичное окно поиска p50/p95; QPS read/write.
3. **Retention** archive и snapshots — одинаковые 3 года или разные; политика purge.
4. **Частота snapshots** per camera (event / periodic / worst case).
5. **Текущие compaction settings** per table + изменения в `cassandra.yaml` если есть.
6. **`nodetool tablestats`** (и при необходимости `cfstats`) по metadata tables.
7. **Tombstone warnings** в logs за 7–30 дней.
8. **SSTable sizes / count** per table; средний row size (sample rows).
9. **Streamserver / backend / LB** — как пишутся и читаются archive + snapshots; bucket names (`vab` / `csb`).
10. **Migration constraints** — dual-read допустим? downtime? объём данных в mixed `vab`; rollback SLA.

---

## 3. Detailed sections

### A. Cassandra schema / DDL

Запросить артефакты и ответы:

| # | Что нужно |
|---|-----------|
| A1 | `CREATE KEYSPACE` — replication class, RF per DC |
| A2 | `CREATE TABLE` — все metadata tables (archive, snapshots, legacy) |
| A3 | Primary key / clustering key — обоснование текущей модели |
| A4 | Secondary indexes, materialized views, UDT |
| A5 | `default_time_to_live`, per-column TTL |
| A6 | `compaction` (class, window, thresholds) per table |
| A7 | `compression` parameters |
| A8 | `gc_grace_seconds` |
| A9 | Типичные **consistency levels** на read/write |
| A10 | Топология: DC names, RF, rack awareness |

**Вопрос:** metadata fragments/snapshots живут **только в Cassandra** или также в filer / другом store?

---

### B. Query patterns

| # | Вопрос |
|---|--------|
| B1 | Доминирует **point lookup** `(camera_id, fragment_id)` или **range** по времени? |
| B2 | Типичное окно range query: **p50 / p95 / p99** (минуты, часы, сутки, неделя)? |
| B3 | **Stitching** — как backend собирает непрерывный поток из сегментов (порядок, gaps)? |
| B4 | Есть ли **cross-camera** queries (списки камер, aggregate)? |
| B5 | **Snapshot lookup** — by ID only, by camera+time, list recent? |
| B6 | **Read QPS / write QPS** (peak и average) на metadata layer |
| B7 | Latency SLA для search API (ms) |
| B8 | Max rows returned per query; pagination |

Сопоставить с [load model §5](CASSANDRA-LOAD-MODEL.md#5-recommendation-для-production-discussion): day vs week bucket.

---

### C. Data volume / growth

| # | Метрика |
|---|---------|
| C1 | Текущее **число строк** per table (или estimate) |
| C2 | **Disk usage** per table (live + SSTables) |
| C3 | **Средний размер строки** metadata (sample 100–1000 rows) |
| C4 | **Активные камеры** сейчас vs план 10k |
| C5 | **Распределение длительности фрагмента** (всегда 20 с или variable) |
| C6 | **Фактический retention** archive / snapshot |
| C7 | **Daily write volume** — rows/day и blob GB/day |
| C8 | Рост за последние 3–12 месяцев (trend) |

Сверить с моделью: 4 320 fragments/camera/day при 20 с.

---

### D. Compaction / tombstones

Запросить **вывод команд** (см. §4) и ответы:

| # | Что смотреть |
|---|--------------|
| D1 | `nodetool tablestats` — partition size estimates, compression ratio |
| D2 | `nodetool cfstats` — если версия Cassandra поддерживает legacy cfstats |
| D3 | `nodetool compactionstats` — pending compactions, throughput |
| D4 | `nodetool tpstats` — thread pool pressure (compaction/read/write) |
| D5 | Logs: `tombstone`, `Too many tombstones`, `ReadRepair` warnings (7–30 d) |
| D6 | Исторические **compaction failures** / long-running compactions |
| D7 | Используются ли **DELETE** vs TTL для expiry |
| D8 | Repair schedule и последний успешный repair |

---

### E. Snapshots / buckets

| # | Вопрос |
|---|--------|
| E1 | Где **blob** snapshots сейчас (bucket name, path pattern) |
| E2 | Всё ли ещё в **`vab`** вместе с archive или уже разделено |
| E3 | **Частота** snapshot per camera (типичная и peak) |
| E4 | **Retention** snapshots vs archive |
| E5 | Где **metadata** snapshots (Cassandra table? filer? тот же `fragments`?) |
| E6 | Как **backend читает** snapshot (URI, presigned, через sideweed/LB) |
| E7 | Миграция: переносить **старые** snapshots в `csb` или только **новые** writes |
| E8 | Объём legacy snapshot data в `vab` (GB, object count) |

Stand сейчас: write/read smoke в **`csb`**; archive на **`video-fragments`** (не `vab`).

---

### F. Streamserver / backend / LB configs

| # | Что запросить |
|---|---------------|
| F1 | Где задаётся **bucket** (env, config file, feature flag) |
| F2 | **Streamserver** — path записи archive fragment и snapshot |
| F3 | **Backend** — read path archive vs snapshot |
| F4 | **LB / sideweed / HAProxy** — routing write vs read |
| F5 | **Feature flags** / env vars для bucket split, metadata store |
| F6 | Диаграмма pipeline (write + read) как в production |
| F7 | Версии / forks sideweed, SeaweedFS, совпадение с stand pin |

---

### G. Migration / compatibility constraints

| # | Вопрос |
|---|--------|
| G1 | Допустим ли **dual-read** (v1 `fragments` → v2 tables) |
| G2 | Допустим ли **dual-write** на переходный период |
| G3 | **Downtime window** для schema migration (ноль / минуты / часы) |
| G4 | Нужна ли **online migration** без остановки записи |
| G5 | Объём **старых данных** в mixed `vab` / legacy metadata |
| G6 | **Rollback** — требования и кто принимает решение |
| G7 | **SLA** на чтение архива старше N дней / legacy URI |
| G8 | Backfill: one-shot job vs continuous; кто запускает |

---

### H. Production environment

| # | Параметр |
|---|----------|
| H1 | Cassandra **version** (exact) |
| H2 | **Node count**, spec CPU/RAM |
| H3 | **Disk type**, capacity, IOPS per node |
| H4 | **RF**, DC layout, rack |
| H5 | **Repair** schedule (`nodetool repair`) |
| H6 | **Backup / restore** (snapshots, Medusa, etc.) |
| H7 | **Monitoring** — Grafana dashboards, alerts (latency, disk, compaction) |
| H8 | Maintenance windows |

---

## 4. Command appendix (read-only)

Команды для админа заказчика — **только чтение**, без destructive ops.  
Подставить реальные `<keyspace>`, `<table>`, пути логов.

### CQL / schema

```bash
# Подключение (host/port/credentials — у заказчика)
cqlsh <host> -e "DESCRIBE KEYSPACES;"
cqlsh <host> -e "DESCRIBE KEYSPACE <keyspace>;"
cqlsh <host> -e "DESCRIBE TABLE <keyspace>.<table>;"
cqlsh <host> -e "SELECT keyspace_name, table_name, bloom_filter_fp_chance, caching, compaction, compression, default_time_to_live, gc_grace_seconds FROM system_schema.tables WHERE keyspace_name = '<keyspace>';"
```

### Cluster health

```bash
nodetool status
nodetool describecluster
nodetool info
```

### Table / compaction metrics

```bash
nodetool tablestats <keyspace>.<table>
# Cassandra 3.x legacy (если доступно):
nodetool cfstats <keyspace>.<table>

nodetool compactionstats
nodetool tpstats
```

### Logs (tombstones)

```bash
# Путь к logs зависит от установки; пример:
grep -i tombstone /var/log/cassandra/system.log | tail -200
grep -iE 'tombstone|Too many tombstones|ReadRepair' /var/log/cassandra/*.log | tail -500
```

### Optional: sample row size (CQL)

```sql
-- Оценка: выборка N строк, измерить размер колонок в приложении или через export
SELECT camera_id, fragment_id, seaweed_fid, size, created_at
FROM <keyspace>.<table> LIMIT 100;
```

**Не запрашивать:** `nodetool clearsnapshot`, `DROP`, `TRUNCATE`, `nodetool drain` без явного change window.

---

## 5. Mapping to ТЗ

| Вопросы / данные | ТЗ §5.2 Snapshot pipeline | ТЗ §5.3 Compaction / search | ТЗ §5.4 Backward compatibility |
|------------------|---------------------------|------------------------------|--------------------------------|
| A (DDL), H (env) | Metadata store для snapshots | Compaction/compression baseline | Текущая schema для dual-read |
| B (query patterns) | Snapshot lookup API | **time_bucket**, TWCS window, range API | Query compatibility v1→v2 |
| C (volume/growth) | Snapshot row growth | Partition width, disk plan | Backfill scope |
| D (compaction/tombstones) | Snapshot table tuning | **TWCS/TTL** decision | DELETE/TTL migration risk |
| E (buckets/snapshots) | **csb/vab**, frequency, read path | Separate `snapshots` table | Legacy `vab` migration |
| F (streamserver/backend) | **Full pipeline** | Write rate to Cassandra | Config rollout |
| G (migration) | csb cutover policy | Online vs offline schema apply | **Dual-read/write, rollback** |
| Short #1–10 | E, F | A, B, C, D | G, E8 |

---

## 6. Что делать после получения ответов (внутренне)

1. Сверить DDL с `schema-v2.cql` и [load model](CASSANDRA-LOAD-MODEL.md).
2. Обновить [CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md) и [CASSANDRA-TASK-STATUS.md](CASSANDRA-TASK-STATUS.md).
3. Решить: dev profile для v2, tuning TWCS, migration plan §5.4.
4. **Не применять** production DDL до sign-off.

---

*Внутренний документ stand repo. Не отправлять заказчику без ревью и согласования формулировок.*
