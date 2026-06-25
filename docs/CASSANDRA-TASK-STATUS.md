# Задача №2 — Cassandra metadata optimization: статус

Краткий статус работ по ТЗ §5.  
Подробный design: [CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md).  
Production facts: [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md) §5.

**Последнее обновление:** stand @ `45daa7b`. Production DDL **частично получен** (`seaweedfs.filemeta`).

---

## 1. Краткая сводка

Задача №2 **закрыта частично** на уровне stand repo:

- **Snapshot blob path (csb):** write (`put_snapshot.sh`) и read (`get_snapshot.sh`) через production-like S3 path; smoke `make test-snapshot` — PASS.
- **Поиск сегментов / range query:** stand-level list по `camera_id` + time range на **runtime** schema (`fragment list`, `list_fragments.sh`); smoke `make test-range-query` — PASS.
- **Compaction / partition model:** prod **`seaweedfs.filemeta` TWCS 6h** (audit); stand `schema-v2.cql` — draft для **application** metadata; **не runtime**.
- **Production:** SeaweedFS metadata DDL **частично получен**; teye keyspace DDL, query patterns, migration §5.4 — **ещё не получены**.

Runtime по-прежнему: `cassandra/schema.cql` → таблица `fragments` (STCS по умолчанию).

---

## 2. Статус по ТЗ

| Пункт ТЗ | Статус | Что сделано | Чем подтверждено | Что осталось |
|----------|--------|-------------|------------------|--------------|
| **5.1 Bucket separation** | Частично | Stand: `video-fragments`/`csb`; prod: **vab** (archive+camera), **csb** read-ready, **esb** events | `make test`, `make test-snapshot`; [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md) | Prod write vab→csb; teye metadata split |
| **5.2 Snapshot pipeline write/read csb** | Частично | Stand smoke; prod camera snapshots ещё **vab** | `make test-snapshot` PASS | streamserver `bucket_name`; teye `camera_base_url` |
| **5.3 Cassandra compaction optimization** | Частично (SeaweedFS metadata) | Prod `seaweedfs.filemeta` TWCS; stand `schema-v2.cql` draft | [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md) | teye DDL; app-layer tuning; `tablestats` |
| **5.3 Segment search / range query** | Частично (stand smoke) | `ListFragmentsByTimeRange` (timeuuid bounds); `fragment list`; `list_fragments.sh`; `make test-range-query` | `make test-range-query` PASS, `go test ./...` PASS | `time_bucket` / `schema-v2` для масштаба; согласование с prod query patterns |
| **5.4 Backward compatibility** | Не реализовано | Описание dual-read/migration в design + комментарии v2; runtime не ломает v1 | Stand smoke tests PASS на v1 schema | Migration job, dual-write, rollback; customer data volume + SLA |

---

## 3. Команды проверки

| Команда | Что проверяет | Последний результат | Ограничения |
|---------|---------------|---------------------|-------------|
| `make test-snapshot` | Snapshot PUT/GET через bucket `csb`, round-trip blob | **PASS** | Metadata в `fragments`; не в `make test`; нужен `make up` + health |
| `make test-range-query` | 3× PUT archive + LIST по camera/time на runtime schema | **PASS** | Timeuuid bounds в одной partition; не в `make test`; не масштаб prod |
| `make test` | Archive PUT/GET `video-fragments` | **PASS** | Не покрывает snapshots/range list |
| `make verify-path` | PUT идёт sideweed → S3 (не direct volume) | **PASS** | Лог-based proof; archive bucket |
| `go test ./...` | Unit-тесты `pkg/fragment` (без integration tag) | **PASS** | Integration: отдельно `make test-go` |

Дополнительно на fresh clone @ `336b451`: `make test-sideweed` PASS (**30/30**), `go test ./...` PASS.

---

## 4. Файлы и артефакты

| Артефакт | Назначение |
|----------|------------|
| [docs/CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md) | Полный design proposal, риски, migration plan |
| [cassandra/schema-v2.cql](../cassandra/schema-v2.cql) | Experimental DDL (`video_fragments_v2`, `snapshots_v2`, TWCS) |
| [docs/CASSANDRA-SCHEMA-V2.md](CASSANDRA-SCHEMA-V2.md) | Как читать v2 CQL; manual apply only |
| [scripts/put_snapshot.sh](../scripts/put_snapshot.sh) | PUT snapshot → `csb` |
| [scripts/get_snapshot.sh](../scripts/get_snapshot.sh) | GET snapshot из `csb` |
| [scripts/test_snapshot.sh](../scripts/test_snapshot.sh) | Smoke PUT+GET snapshot |
| [scripts/list_fragments.sh](../scripts/list_fragments.sh) | LIST metadata по camera + RFC3339 range |
| [scripts/test_range_query.sh](../scripts/test_range_query.sh) | Smoke range query |
| `cmd/fragment list` | CLI list (Cassandra only) |
| Makefile `test-snapshot` / `test-range-query` | Отдельные smoke targets |

**Runtime schema:** [cassandra/schema.cql](../cassandra/schema.cql) (не менялся в рамках Задачи №2).

**История commits (опубликованы на `origin/main`):** `3cc7c96`, `5877202`, `9f134a1`, `4e2e0b6` и последующие root commits.

---

## 5. Явные ограничения

- Archive bucket на stand: **`video-fragments`**, не production **`vab`**.
- Metadata archive и snapshots: **одна таблица** `video_archive.fragments` в runtime.
- **`schema-v2.cql` не подключена** (не в docker-compose `cql-init`).
- **TWCS / TTL не применены** в runtime (default STCS).
- **Production** streamserver / backend / LB configs **отсутствуют** в stand repo.
- **Production Cassandra DDL** от заказчика **не получен**.
- **Migration / backward compatibility** (dual-read/write, backfill) **не реализованы** в коде.

---

## 6. Рекомендуемые следующие шаги

1. **Получить от заказчика:** см. внутренний [CASSANDRA-CUSTOMER-QUESTIONS.md](CASSANDRA-CUSTOMER-QUESTIONS.md) (DDL, query patterns, metrics, pipeline); также §8 [CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md).
2. **Dev-only:** compose profile для ручного apply `schema-v2.cql` (без замены `schema.cql`).
3. **Load model / benchmark:** [CASSANDRA-LOAD-MODEL.md](CASSANDRA-LOAD-MODEL.md) (rows/partition, 3y volume); при необходимости — benchmark profile.
4. **Customer questions:** checklist готов — [CASSANDRA-CUSTOMER-QUESTIONS.md](CASSANDRA-CUSTOMER-QUESTIONS.md); перед внешним запросом — ревью формулировок.

До sign-off с заказчиком: **не деплоить** production DDL/configs и **не подменять** runtime schema.

---

*Документ фиксирует статус Задачи №2; не заменяет [CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md).*
