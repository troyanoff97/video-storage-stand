# Cassandra schema v2 (experimental draft, не runtime)

Файл DDL: [cassandra/schema-v2.cql](../cassandra/schema-v2.cql)

Контекст: [CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md) (Задача №2, design proposal).

## Статус

| | |
|---|---|
| **Runtime stand** | **не использует** v2 — только [schema.cql](../cassandra/schema.cql) |
| **docker-compose** | `cql-init` применяет только `schema.cql` |
| **Production** | **не применять** без DDL и метрик от заказчика |

## Таблицы

### `video_fragments_v2`

Metadata видео-фрагментов (archive).

| PK component | Роль |
|--------------|------|
| `(camera_id, time_bucket)` | partition — ограничение ширины vs v1 |
| `fragment_start` | clustering DESC — time-ordered segments |
| `fragment_id` | clustering DESC — tie-breaker (timeuuid) |

| Column | Назначение |
|--------|------------|
| `bucket` | `vab` (production); stand transition: `video-fragments` |
| `object_key` / `object_uri` | S3 location |
| `schema_version` | dual-read routing (v1 vs v2) |

**Compaction:** TWCS, dev window 1 DAY. Production — после `nodetool tablestats`.

### `snapshots_v2`

Metadata snapshots.

| PK component | Роль |
|--------------|------|
| `(camera_id, time_bucket)` | partition |
| `snapshot_time`, `snapshot_id` | clustering DESC |

| Column | Назначение |
|--------|------------|
| `bucket` | **`csb`** (обязательно для production) |

**Compaction:** TWCS 7 DAYS в draft; **LCS** — альтернатива при частых point reads (зависит от query pattern заказчика).

### Legacy `fragments` (v1)

Остаётся runtime-таблицей stand. Dual-read: при отсутствии строки в v2 — читать v1.

## Как применить вручную (dev only)

```bash
# Stand должен быть up; НЕ часть make up / cql-init
docker compose cp cassandra/schema-v2.cql cassandra:/tmp/schema-v2.cql
docker compose exec -T cassandra cqlsh -f /tmp/schema-v2.cql
docker compose exec -T cassandra cqlsh -e "DESCRIBE TABLE video_archive.video_fragments_v2;"
```

Откат v2 tables (dev only):

```cql
DROP TABLE IF EXISTS video_archive.video_fragments_v2;
DROP TABLE IF EXISTS video_archive.snapshots_v2;
```

## Что проверить перед production

1. Согласовать PK с реальными запросами backend (range vs point).
2. Подтвердить bucket names: `vab` / `csb`.
3. Прогнать TWCS/LCS на копии prod data.
4. Спланировать dual-read / migration (см. CASSANDRA-OPTIMIZATION.md §6).
