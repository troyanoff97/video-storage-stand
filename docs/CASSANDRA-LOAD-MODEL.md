# Cassandra metadata — load / capacity model (ТЗ)

Оценка объёма metadata для видеоархива по вводным ТЗ.  
Связанные документы: [CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md), [CASSANDRA-SCHEMA-V2.md](CASSANDRA-SCHEMA-V2.md), [CASSANDRA-TASK-STATUS.md](CASSANDRA-TASK-STATUS.md).

**Статус:** расчётная модель для обсуждения с заказчиком; не DDL и не runtime config.

---

## 1. Вводные (ТЗ)

| Параметр | Значение |
|----------|----------|
| Камеры | 10 000 |
| Длительность фрагмента | 20 с (MP4) |
| Retention archive | 3 года (~1 095 дней) |
| Write throughput (blob) | несколько GB/s (SeaweedFS/S3; **не** Cassandra) |
| Workload | video fragments + snapshots |
| Runtime PK | `(camera_id, fragment_id)` |
| Proposal v2 PK | `(camera_id, time_bucket)` + clustering по времени |

---

## 2. Fragment count model

### 2.1 Формулы

```
fragments_per_camera_per_second = 1 / fragment_duration_sec
fragments_per_camera_per_minute = 60 / fragment_duration_sec
fragments_per_camera_per_hour   = 3600 / fragment_duration_sec
fragments_per_camera_per_day    = 86400 / fragment_duration_sec
fragments_per_camera_per_year   = fragments_per_camera_per_day × 365
fragments_per_camera_3y         = fragments_per_camera_per_day × 365 × 3

total_fragments = fragments_per_camera × cameras
```

При **fragment_duration = 20 с**:

```
fragments_per_camera_per_minute = 60 / 20 = 3
fragments_per_camera_per_hour   = 180
fragments_per_camera_per_day    = 4 320
fragments_per_camera_per_year   = 1 576 800
fragments_per_camera_3y         = 4 730 400  ≈ 4.73×10⁶
```

### 2.2 Сводная таблица (10 000 камер)

| Период | На 1 камеру | На 10 000 камер |
|--------|-------------|-----------------|
| Минута | 3 | 30 000 |
| Час | 180 | 1 800 000 |
| Сутки | 4 320 | **43.2×10⁶** (43.2 M) |
| Год (365 д) | 1.577×10⁶ | **15.77×10⁹** (15.8 B) |
| 3 года | 4.73×10⁶ | **47.3×10⁹** (47.3 B) |

### 2.3 Steady-state metadata write rate (только fragments)

```
writes_per_sec ≈ (cameras × fragments_per_camera_per_day) / 86400
              ≈ 43.2×10⁶ / 86400 ≈ 500 inserts/s (10k камер)
```

Blob throughput (GB/s) идёт в object storage; Cassandra хранит **только metadata** (~сотни байт на строку).

---

## 3. Current schema risk — wide partition

**PK runtime:** `(camera_id, fragment_id)` → одна partition = **все** фрагменты камеры за весь retention.

| Горизонт | Строк в partition (1 камера) | Комментарий |
|----------|------------------------------|-------------|
| 1 сутки | 4 320 | Уже заметный range scan внутри partition |
| 1 год | 1 576 800 | ~1.6M rows — repair/read pressure |
| 3 года | **4 730 400** | **~4.7M rows** — классический wide partition |

### Почему ~4.7M rows/camera — риск

1. **Размер partition на диске** растёт без верхней границы по времени; compaction/repair обрабатывают всё сразу.
2. **Range query** по времени (`fragment_id` timeuuid) всё равно читает **одну** огромную partition → высокий read amplification при длинном retention.
3. **Hot cameras** (выше средней частоты) — ещё шире partition + write hotspot на один token range.
4. **Tombstones / DELETE** по возрасту на одной partition — опасны (см. §7).
5. Cassandra рекомендует держать partition **сотни KB – низкие миллионы** строк в зависимости от row size; 4.7M × 200–1000 B = **сотни MB – несколько GB metadata на камеру** в одной partition до учёта SSTable overhead.

Stand `make test-range-query` доказывает **корректность** timeuuid list на малых объёмах; масштаб ТЗ требует **time bucketing** (`schema-v2`).

---

## 4. Time bucket comparison

Сравнение для **archive fragments** (не snapshots).  
Предположение: календарный **day** = 1 сутки записи; **week** = 7 дней; **month** = 30 дней (календарный месяц 28–31 — уточнять в prod).

| Метрика | Day bucket | Week bucket | Month bucket (30 d) |
|---------|------------|-------------|---------------------|
| Rows / partition / camera (max) | **4 320** | **30 240** | **129 600** |
| Partitions / camera за 3 года | **1 095** | **~157** | **~37** |
| Total partitions (10k cameras, 3y) | **10.95×10⁶** | **~1.57×10⁶** | **~370×10³** |
| Range query 10 мин – 1 ч | 1 partition, малый scan | 1 partition | 1 partition |
| Range query 1 сутки | 1 partition (полный scan дня) | 1 partition (часть недели) | 1 partition (часть месяца) |
| Range query 7 суток | **7 partitions** | **1 partition** | 1 partition |
| Range query 30 суток | **~30 partitions** | **~4–5 partitions** | **1 partition** (широкий scan) |
| Compaction (TWCS) | Окно 1 DAY естественно | Окно 7 DAYS | Окно 30 DAYS; крупные SSTables |
| Плюсы | Узкие partitions; TTL по дням; предсказуемый размер | Меньше partition count; меньше fan-out на недельные запросы | Минимум partitions |
| Минусы | Больше partitions всего; multi-day = multi-partition read | Partition в 7× шире day | **Широкая partition**; тяжёлый scan/TTL; month часто избыточен |

**Влияние на range queries:** чем шире bucket относительно типичного окна поиска, тем больше **лишних строк** читается внутри одной partition. Чем уже bucket, тем больше **partition fan-out** при длинных окнах (coordination overhead).

**Влияние на compaction:** TWCS группирует SSTables по временным окнам. Bucket и `compaction_window_size` логично **выравнивать** (day↔1d, week↔7d), иначе старые и новые данные смешиваются в одних SSTables.

---

## 5. Recommendation (для production discussion)

### Default для обсуждения: **day bucket**

- ~4 320 rows/partition/camera — управляемый размер.
- Согласуется с draft `schema-v2.cql` (`time_bucket date`, TWCS window 1 DAY).
- Типичный поиск «за последний час / сутки» укладывается в **1 partition** с умеренным scan.

### Альтернатива: **week bucket**

- Если заказчик подтвердит, что **типичное окно поиска — несколько суток / неделя**, а не минуты.
- Меньше общее число partitions (~1.57M vs ~11M на 10k камер).

### Month bucket — обычно **не рекомендуется** как default

- ~130k rows/partition/camera даже при 20 с фрагментах.
- Запрос «за 1 час» читает partition за весь месяц.
- Сложнее TTL и compaction без wide scans.

### Финальный выбор зависит от query patterns

| Типичное окно поиска | Предпочтительный bucket |
|----------------------|-------------------------|
| 1–10 минут, до 1 часа | **day** (или hour — не в draft v2) |
| 1 сутки | **day** |
| Несколько суток, неделя | **week** или day + multi-partition read |
| Месяц+ | Отдельный aggregate index / иной access path; не month partition по умолчанию |

---

## 6. Metadata size — rough estimate

Только **archive fragments**, 47.3×10⁹ строк за 3 года (10k камер).  
Row size **гипотеза** (колонки + PK overhead, без учёта SSTable/index):

| Row size (hypothesis) | Raw metadata (3y, 10k cam) | × RF=3 (illustrative) |
|---------------------|----------------------------|------------------------|
| 200 B | **~9.5 TB** | ~28 TB |
| 500 B | **~24 TB** | ~71 TB |
| 1 KiB | **~48 TB** | ~145 TB |

**Не включено:** Cassandra storage overhead (SSTables, bloom filters, compression ratio, tombstones, snapshots таблица, secondary indexes, repairs). Реальный диск **выше** на коэффициент 1.5–3× и более.

Фактический row size нужно взять из production: `DESCRIBE TABLE`, sample rows, `nodetool tablestats`.

---

## 7. Compaction implications

### Почему TWCS для time-series

- Inserts time-ordered; старые окна редко перезаписываются.
- TWCS компактирует SSTables **внутри временного окна** → меньше write amplification vs STCS на длинном retention.
- Упрощает вытеснение старых окон при согласованном **TTL**.

### Связь time_bucket и TWCS window

| time_bucket | Разумный TWCS window (старт обсуждения) |
|-------------|----------------------------------------|
| day | 1 DAY |
| week | 7 DAYS |
| month | 7–30 DAYS (требует метрик) |

Несовпадение bucket (day) и огромного TWCS window (30d) смешивает свежие и старые SSTables.

### Retention / TTL

- TTL ≈ retention (3 года) на уровне table или bucket purge.
- `gc_grace_seconds` согласовать с repair interval.
- **Массовые DELETE** по старым данным → tombstones → read repair storms; предпочтительнее **TTL** или drop целых time windows / TWCS expired windows.

---

## 8. Snapshot impact

Частота snapshots в ТЗ **не зафиксирована**. Формула:

```
total_snapshot_rows = snapshots_per_camera_per_day × cameras × retention_days
```

Retention snapshots = 3 года (1 095 дней), cameras = 10 000.

| Сценарий | Snapshots / camera / day | Total rows (3y, 10k cam) |
|----------|------------------------|---------------------------|
| 1 / hour | 24 | **262.8×10⁶** (~263 M) |
| 1 / 10 min | 144 | **1.58×10⁹** (~1.6 B) |
| 1 / min | 1 440 | **15.77×10⁹** (~15.8 B) |

При частых snapshots metadata snapshots может **сопоставиться или превысить** archive по числу строк → таблица **`snapshots_v2`** (bucket `csb`), отдельный PK/compaction, не смешивать с archive в `fragments`.

---

## 9. Questions needed from production

1. **Реальные query windows:** p50/p95 длительность поиска (минуты / часы / сутки)?
2. **Частота snapshot** per camera (event-driven / periodic / on motion)?
3. **Retention snapshot** vs archive (одинаковые 3 года или короче)?
4. **Фактический row size** и средний SSTable size (`tablestats`).
5. **RF и DC** (NetworkTopologyStrategy).
6. **Compression** на tables (LZ4/Snappy) — effective disk multiplier.
7. **`compactionstats`**, tombstone warnings, read latency SLA для search API.
8. Допустимая задержка range query (ms) и max rows per response.

Чеклист расширяет §8 [CASSANDRA-OPTIMIZATION.md](CASSANDRA-OPTIMIZATION.md).

---

## 10. Summary

| Тема | Вывод |
|------|--------|
| Fragments 3y / 10k cam | **~47.3 B** rows |
| Runtime `(camera_id)` only | **~4.73 M** rows/partition/camera — wide partition |
| Рекомендуемый bucket (draft) | **day**; week — если окна поиска многодневные |
| Month bucket | Обычно слишком широкий для 20 с фрагментов |
| Metadata disk (order of magnitude) | **~10–50 TB raw** при 200 B–1 KiB/row до RF/overhead |
| Snapshots | Отдельная таблица; сценарий 1/min → **~15.8 B** rows |

---

*Модель создана для Задачи №2; не применять без production DDL и метрик заказчика.*
