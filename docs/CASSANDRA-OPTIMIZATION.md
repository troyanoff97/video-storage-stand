# Задача №2 — Оптимизация Cassandra metadata storage (design proposal)

Документ фиксирует **текущее состояние stand repo**, риски и **целевую архитектуру** по ТЗ §5.1–5.4.  
Это **design proposal** — не применять DDL и runtime без production DDL и согласования с заказчиком.

**Stand repo:** `git@github.com:troyanoff97/video-storage-stand.git`  
**Связанные документы:** [TZ-DEVIATIONS.md](TZ-DEVIATIONS.md), [PRODUCTION-DEPLOY.md](PRODUCTION-DEPLOY.md)

---

## 1. Current state

### 1.1 Cassandra-схема (stand)

Источник: `cassandra/schema.cql`

| Параметр | Значение |
|----------|----------|
| Keyspace | `video_archive` |
| Replication | `SimpleStrategy`, RF=1 |
| Таблица | `fragments` (единственная) |
| Columns | `camera_id`, `fragment_id` (timeuuid), `seaweed_fid`, `size`, `created_at` |
| Primary key | `(camera_id, fragment_id)` |
| Clustering | `fragment_id DESC` |
| Indexes | нет |
| TTL | нет |
| Compaction | не задана → default **SizeTieredCompactionStrategy (STCS)** |
| Отдельная таблица snapshots | нет |

Go-клиент (`pkg/fragment/cassandra.go`): consistency `Quorum`, только `INSERT` и point `SELECT`.

### 1.2 PUT/GET metadata pipeline (stand)

**PUT fragment** (`scripts/put_fragment.sh` → `fragment put`):

1. `fragment_id = TimeUUID()`
2. Blob → S3 via sideweed: `s3://{S3_BUCKET}/{camera_id}/{fragment_id}.bin`
3. Cassandra: `INSERT INTO fragments (...)`
4. Verify: roundtrip GET из S3

**PUT snapshot** (`scripts/put_snapshot.sh`):

1. `S3_BUCKET=csb` → тот же pipeline, что и fragment
2. Blob в bucket **csb**
3. Metadata в **ту же таблицу** `fragments`; `camera_id` = переданный `snapshot_id`

**GET snapshot** (`scripts/get_snapshot.sh` → `get_fragment.sh` → `fragment get`):

1. Аргументы: `snapshot_id` (= `camera_id` в metadata) и `fragment_id` из вывода PUT
2. Blob по `seaweed_fid` (`s3://csb/...`) через read path (HAProxy → S3)
3. Smoke: `make test-snapshot` (отдельный target, не входит в `make test`)
4. Metadata по-прежнему в `fragments`; `schema-v2` не runtime

**GET fragment** (`scripts/get_fragment.sh` → `fragment get`):

1. `SELECT ... WHERE camera_id = ? AND fragment_id = ?`
2. Blob по `seaweed_fid` (bucket из URI) через read path (HAProxy → S3)

**LIST fragments by time** (`scripts/list_fragments.sh` → `fragment list`):

1. `SELECT ... WHERE camera_id = ? AND fragment_id >= MinTimeUUID(from) AND fragment_id <= MaxTimeUUID(to) LIMIT ?`
2. Stand smoke: `make test-range-query` (не в `make test`)
3. На текущей schema — timeuuid bounds внутри одной партиции `camera_id`; для production масштаба нужен `time_bucket` / `schema-v2`

Range-query по времени и записи metadata через filer **нет** (кроме stand list выше).

### 1.3 Buckets (stand vs ТЗ)

| Назначение | ТЗ | Stand сейчас |
|------------|-----|--------------|
| Video archive (blob) | `vab` | `video-fragments` (default `S3_BUCKET`) |
| Snapshots (blob) | `csb` | `csb` (`put_snapshot.sh`) |

Разделение blob на уровне S3 для snapshots **частично есть**. Имя production bucket `vab` на стенде **не используется**.  
Metadata archive и snapshots **не разделены** — одна таблица `fragments`.

### 1.4 Отличие от production (важно)

По [TZ-DEVIATIONS.md](TZ-DEVIATIONS.md):

- В production метаданные пишет **SeaweedFS/filer**, не тестовый клиент.
- `streamserver`, `backend`, load balancer конфигурации **отсутствуют** в stand repo.
- Production Cassandra DDL **не предоставлен**.

Stand schema **нельзя** считать production schema без подтверждения заказчика.

---

## 2. Problems

### 2.1 PRIMARY KEY `(camera_id, fragment_id)` при масштабе ТЗ

Оценка нагрузки (из ТЗ):

- ~10 000 камер
- fragment ≈ 20 с (MP4)
- retention 3 года
- поиск сегментов по camera / time range

**Строк на камеру за 3 года:**  
`3 × 365 × 24 × 3600 / 20 ≈ 4.7×10⁶` fragments/camera

**Partition key = `camera_id`** → одна партиция на камеру растёт до миллионов строк. Риски:

- широкие партиции (wide partition): медленный read/repair, pressure на memtable и compaction;
- unbounded partition growth без time bucketing;
- hotspot на hot cameras.

`fragment_id` как timeuuid даёт time-order **внутри** партиции, но не ограничивает её ширину.

### 2.2 Default STCS и time-series архив

**SizeTieredCompactionStrategy** по умолчанию:

- объединяет SSTables похожего размера, без учёта времени;
- для append-only time-series с retention плохо предсказуем: крупные SSTables, долгие compaction, read amplification;
- не выравнивает данные по временным окнам → сложнее TTL/purge по возрасту.

Для архива с time-ordered inserts и 3-year retention обычно рассматривают **TWCS** или bucketed partitions + TWCS.

### 2.3 Отсутствие TTL / retention policy

Без TTL:

- данные 3-летней давности остаются до явного DELETE;
- массовый DELETE → tombstones → read latency, disk bloat;
- нет автоматического lifecycle на уровне Cassandra.

Retention должен быть явной политикой (TTL, compaction windows, archival), согласованной с заказчиком.

### 2.4 Смешивание archive и snapshot metadata

Сейчас snapshots пишутся в `fragments` с тем же PK-моделью:

- разные паттерны доступа (snapshots реже, крупнее, другой retention);
- нельзя независимо настроить compaction/TTL;
- риск путаницы `camera_id` vs `snapshot_id` в одной таблице;
- усложняет миграцию §5.1 (разделение `vab` / `csb` на уровне metadata).

### 2.5 Почему stand ≠ production

| Аспект | Stand | Production (ожидание по ТЗ/docs) |
|--------|-------|--------------------------------|
| Metadata writer | Go client `pkg/fragment` | filer / backend |
| Keyspace/tables | `video_archive.fragments` | **неизвестно** |
| Bucket archive | `video-fragments` | `vab` |
| Pipeline snapshots | только `put_snapshot.sh` | streamserver + backend + LB |
| Compaction tuning | нет | требуется §5.3 |

Любая оптимизация stand без production DDL может не перенестись на prod.

---

## 3. Target architecture proposal (не применять)

> Ниже — **предложение для согласования**, не DDL для немедленного deploy.

### 3.1 Blob storage (S3 / SeaweedFS)

| Тип | Bucket | Объектный ключ (пример) |
|-----|--------|-------------------------|
| Video archive | `vab` | `{camera_id}/{segment_start}/{fragment_id}.mp4` |
| Snapshots | `csb` | `{camera_id}/{snapshot_id}.bin` или `{snapshot_id}.bin` |

Stand позже может переименовать default `video-fragments` → `vab` **после** согласования URI в существующих metadata.

### 3.2 Metadata tables (предложение)

**Таблица A — video fragments / segments**

Черновик DDL: [cassandra/schema-v2.cql](../cassandra/schema-v2.cql) → `video_fragments_v2` (experimental, не runtime).  
Подробнее: [CASSANDRA-SCHEMA-V2.md](CASSANDRA-SCHEMA-V2.md).

```text
video_archive.fragments_v2
  PK: (camera_id, day_bucket)     -- day_bucket: date или unix_day
  CK: segment_start timestamp
  CK: fragment_id timeuuid
  Columns: object_uri, size, codec, duration_ms, created_at, schema_version
```

**Таблица B — snapshots**

Черновик DDL: [cassandra/schema-v2.cql](../cassandra/schema-v2.cql) → `snapshots_v2` (experimental, не runtime).

```text
video_archive.snapshots
  PK: (camera_id, month_bucket)    -- или snapshot_id prefix
  CK: snapshot_time timestamp
  CK: snapshot_id timeuuid
  Columns: object_uri, size, created_at, schema_version
```

Альтернатива для snapshots: PK = `snapshot_id` если только point lookup по ID.

### 3.3 Query patterns (целевые)

| Запрос | Доступ |
|--------|--------|
| GET fragment by ID | point: `(camera_id, fragment_id)` или denormalized lookup table |
| Range by camera + time | `WHERE camera_id = ? AND day_bucket IN (...) AND segment_start >= ? AND segment_start < ?` |
| GET snapshot by ID | `snapshots` point lookup |
| List snapshots for camera | partition scan по `month_bucket` |

При необходимости — **materialized view** или вторая таблица `fragments_by_time` (denormalization), если production уже использует другой паттерн.

### 3.4 Backward compatibility (концепт)

- Старые строки в `fragments` остаются читаемыми.
- Новые записи → `fragments_v2` + `snapshots`.
- `seaweed_fid` / `object_uri` поддерживает и `s3://video-fragments/...`, и `s3://vab/...` в transition period.
- Поле `schema_version` в новых таблицах для routing read path.

---

## 4. Compaction strategy

### 4.1 Video fragments — TimeWindowCompactionStrategy (TWCS)

**Почему TWCS:** inserts time-ordered, retention time-bound, purge по окнам естественен.

**Dev / stand (гипотеза для benchmark):**

```text
compaction = {
  'class': 'TimeWindowCompactionStrategy',
  'compaction_window_size': '1',
  'compaction_window_unit': 'DAYS',
  'max_threshold': '32',
  'min_threshold': '4'
}
```

**Production (гипотеза — требует метрик):**

```text
compaction_window_unit: DAYS
compaction_window_size: 1–7        -- от размера fragment и write rate
max_threshold: 32–64
min_threshold: 4–8
tombstone_compaction_interval: 86400
```

### 4.2 Метрики для точного выбора

Запросить с production (nodetool / Prometheus):

| Метрика | Зачем |
|---------|-------|
| `nodetool tablestats` — partitions, row count, partition size | wide partition risk |
| `nodetool compactionstats` | длительность, backlog |
| SSTable count / size per table | STCS vs TWCS |
| Tombstone warnings в logs | DELETE/TTL tuning |
| Write rate (inserts/s) per table | window size |
| Read latency p95/p99 по типам запросов | read amplification |
| Disk growth / month | retention sizing |

### 4.3 Snapshots — варианты

| Вариант | Когда |
|---------|-------|
| **TWCS** (окно 7–30 DAYS) | регулярные snapshots, time-ordered |
| **LCS** | умеренный объём, частый point read, мало wide scans |
| **STCS** | только если мало данных и нет retention pressure (не рекомендуется для 3y) |

Snapshots обычно **реже** и **крупнее** fragments → отдельная таблица и отдельная compaction policy.

---

## 5. Tombstones / retention

### 5.1 Как уменьшать tombstones

- Предпочитать **TTL** вместо массового `DELETE`.
- Удалять **по time window** (partition bucket), не всю партицию `camera_id` одним запросом.
- Избегать частых `UPDATE` на wide rows; append-only inserts предпочтительнее.
- `gc_grace_seconds` не уменьшать без понимания repair schedule.

### 5.2 TTL

- TTL на уровне таблицы или column — для 3-year retention после согласования.
- Пример: `fragments_v2` TTL = 94608000 s (≈3 года) **только после** тестов на копии prod.
- Snapshots могут иметь **другой TTL**.

### 5.3 gc_grace_seconds

- Default 864000 s (10 дней) — tombstones живут до gc после compaction.
- При агрессивном TTL/DELETE может потребоваться tuning вместе с `tombstone_compaction_interval`.
- **Нельзя** менять на production без staging и nodetool checks.

### 5.4 Запрет без тестов

Не включать на production без:

1. backup / snapshot restore plan;
2. нагрузочного теста на копии;
3. мониторинга tombstone warnings 24–72 ч;
4. rollback DDL / dual-read path.

---

## 6. Migration / backward compatibility

### 6.1 Безопасный план (phased)

**Phase 0 — read-only inventory**

- Экспорт production DDL, sample queries, объём данных в `vab` / metadata store.

**Phase 1 — dual write (optional)**

- New writes → `fragments_v2` + `snapshots` + blob в `vab`/`csb`.
- Old writes отключены только после валидации.

**Phase 2 — dual read**

```text
if schema_version == 2 or found in fragments_v2:
    read v2
else:
    read legacy fragments
```

**Phase 3 — backfill (если нужно)**

- Migration job: scan legacy `fragments` → insert v2 (batch, throttle).
- Идемпотентность по `(camera_id, fragment_id)`.
- Прогресс в отдельной таблице `migration_checkpoint`.

**Phase 4 — deprecate legacy**

- Read-only на `fragments` (старая таблица).
- TTL или archive export перед drop (не раньше согласования).

### 6.2 Rollback

- Feature flag: `USE_METADATA_V2=false` → только legacy read/write.
- Новые таблицы не удалять до стабилизации.
- Blob buckets: dual buckets (`video-fragments` + `vab`) читаемы по URI в metadata.

### 6.3 Проверка «архив не ломается»

- Regression: PUT/GET существующих fragment_id из legacy table.
- Chaos / acceptance: `make test`, `verify-path` без изменения production path.
- Snapshot: write `csb`, read по сохранённому URI.
- Сравнение row counts до/after migration job.

---

## 7. What we can safely implement in stand later

Без production DDL — только **experimental** в stand repo:

| Item | Описание |
|------|----------|
| `cassandra/schema-v2.cql` | **Добавлен (experimental draft):** TWCS + `video_fragments_v2` + `snapshots_v2`; не подменяет `schema.cql`, не в `cql-init` — см. [CASSANDRA-SCHEMA-V2.md](CASSANDRA-SCHEMA-V2.md) |
| `scripts/get_snapshot.sh` | **Добавлен:** GET из `csb` по `snapshot_id` + `fragment_id`; smoke `make test-snapshot` |
| `scripts/list_fragments.sh` | **Добавлен:** LIST по `camera_id` + RFC3339 range на runtime `fragments`; smoke `make test-range-query` |
| Range query API | Go `fragment list` + script (stand); production scale → `time_bucket` / `schema-v2` |
| Rename bucket default | `video-fragments` → `vab` с env override для совместимости |
| Tests | archive PUT/GET (`make test`); snapshot PUT/GET (`make test-snapshot`); range list (`make test-range-query`) |
| Load model doc | rows/partition, write rate, disk 3y |
| Benchmark compose profile | отдельный profile, не менять default `make up` |

Всё выше — **после** отдельного промпта и без push в production configs заказчика.

---

## 8. What we need from customer

Конкретный чеклист запросов:

1. **Production Cassandra DDL** (keyspaces, tables, UDT, MV, indexes).
2. **Primary / clustering keys** и обоснование текущей модели.
3. **Реальные CQL/API запросы** backend (point vs range, latency SLA).
4. Как **streamserver** пишет snapshots (bucket, key, metadata path).
5. Где **хранится metadata snapshots** сейчас (Cassandra / filer / другое).
6. **Retention** fragments vs snapshots (одинаковый 3 года?).
7. Текущие **compaction settings** per table (`DESCRIBE TABLE` / `cassandra.yaml`).
8. Вывод **`nodetool tablestats`** и **`compactionstats`** (или Grafana).
9. **Tombstone warnings** из logs за последние 7–30 дней.
10. **SSTable sizes**, количество SSTables per table.
11. **Объём данных** в bucket `vab` (и были ли snapshots внутри `vab` до разделения).
12. Нужна ли **online migration** без downtime.
13. План переименования / split bucket `vab` → `vab` + `csb` для **существующих** объектов.
14. Подтверждение: metadata в prod = **filer only** или Cassandra тоже активна.

---

## 9. Status by ТЗ

| Пункт | Current status | What is done | What is missing | Next action | Dependency |
|-------|----------------|--------------|-----------------|-------------|------------|
| **5.1 Bucket separation** | Частично | S3: `csb` для snapshots; archive на `video-fragments` | Bucket `vab`; metadata split; legacy `vab` mixed data | Согласовать имена buckets; dual-uri read | Customer: текущая layout `vab` |
| **5.2 Snapshot pipeline** | Частично (stand blob read/write) | `put_snapshot.sh` + `get_snapshot.sh` → sideweed/S3 `csb`; `make test-snapshot` | streamserver/backend/LB configs; metadata в отдельном store (`snapshots_v2` draft only) | Получить production pipeline diagram | Customer configs |
| **5.3 Cassandra compaction** | Не сделано в runtime (experimental draft готов) | Минимальная schema в stand (default STCS); **draft** `schema-v2.cql` с TWCS; stand range-list на v1 schema | TWCS/TTL не в runtime; wide partitions at scale | Применить v2 в dev profile + `tablestats` | Production DDL + metrics |
| **5.4 Backward compatibility** | Не сделано (requires production DDL) | Stand не ломает локальный архив; dual-read описан в design + v2 comments | Dual read/write, migration job не реализованы | Phased plan после DDL | Customer data volume + SLA |

---

## 10. Final summary

**Что в stand уже есть:**

- Production-like **blob path**: fragments (`video-fragments`) и snapshots (`csb`) через sideweed → S3.
- Минимальная Cassandra **`video_archive.fragments`** для point lookup тестового клиента.
- Acceptance stack проверен (fresh clone, S3 path, sideweed gate).

**Что не реализовано (Задача №2):**

- Оптимизация compaction (TWCS, tuning).
- Разделение metadata archive / snapshots.
- Bucket `vab`, production streamserver/backend/LB §5.2.
- Migration и backward compatibility §5.4.

**Почему следующий шаг — production DDL и query patterns:**

Stand schema — **упрощение для тестов**; production metadata может жить в filer или в другой Cassandra-модели. Без фактических DDL и запросов нельзя безопасно выбрать partition key, TWCS windows и migration.

**Что можно прототипировать позже в stand (безопасно):**

- `schema-v2.cql` + experimental profile;
- benchmarks;
- документация и тесты — **без** замены production configs до sign-off.

---

*Документ создан по результатам read-only аудита stand @ `77eea5c`. Runtime-код, `schema.cql` и `docker-compose.yml` не изменялись.*
