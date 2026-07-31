# Cassandra `seaweedfs.filemeta` (этап 3)

Scope: **только** filer-слой SeaweedFS (`seaweedfs.filemeta`). teye / отдельный app-кластер **не входят**.

**No production ALTER has been applied from this repo.** Customer applies changes themselves.

Customer (2026-07-31): TWCS 2d already applied in **several** environments under read pressure; **not yet** added to the main playbook — treat [05-PRODUCTION-RUNBOOKS.md](05-PRODUCTION-RUNBOOKS.md) + `cassandra/filemeta_twcs_*.cql` as the playbook source for remaining / primary envs.

## Goal

Reduce SSTable pile-up under ~30d object TTL and improve read fan-out by widening TWCS window **6 HOURS → 2 DAYS**.

| Window | ~windows over 30d | Expected SSTable pressure |
|--------|-------------------|---------------------------|
| 6h (baseline before change) | ~120 | Observed **187** SSTables |
| 2d (target / already in some envs) | ~15 | Fewer overlapping windows to read |

## Production baseline (customer, 2026-07-31)

### DDL

```cql
CREATE TABLE seaweedfs.filemeta (
    directory text,
    name text,
    meta blob,
    PRIMARY KEY (directory, name)
) WITH CLUSTERING ORDER BY (name ASC)
    AND compaction = {
      'class': 'org.apache.cassandra.db.compaction.TimeWindowCompactionStrategy',
      'compaction_window_size': '6',
      'compaction_window_unit': 'HOURS',
      'max_threshold': '32',
      'min_threshold': '4',
      'tombstone_compaction_interval': '86400',
      'unchecked_tombstone_compaction': 'true'
    }
    AND compression = {
      'chunk_length_in_kb': '16',
      'class': 'org.apache.cassandra.io.compress.LZ4Compressor'
    }
    AND default_time_to_live = 0
    AND gc_grace_seconds = 3600
    -- (+ caching / bloom / speculative_retry as in DESCRIBE; unchanged by this stage)
    ;
```

### tablestats (summary)

| Metric | Value |
|--------|-------|
| SSTable count | **187** |
| Space used (live) | ~6.3 GiB (6754316010 B) |
| Partitions (estimate) | ~7.77M |
| Local read latency | 0.337 ms |
| Local write latency | 0.024 ms |
| Percent repaired | **0.0** |
| Droppable tombstone ratio | **0.873** |
| Bloom false ratio | 0.00762 |

Top partitions by size (dated sample): `/buckets/esb/2026/4/*` — tens of MiB each (wide dirs, not a TWCS-window issue).

### tablehistograms (summary)

| Pct | Read µs | Write µs | SSTables touched | Part size |
|-----|---------|----------|------------------|-----------|
| 50% | 310 | 20 | 0 | 124 B |
| 95% | 535 | 50 | 0 | 1597 B |
| 99% | 924 | 50 | 1 | 2759 B |
| Max | 1916 | 86 | **10** | ~86 MiB |

Local p99 read is still sub-ms on this snapshot; customer reports **read degradation correlated with SSTable growth**. Max SSTables-per-read = 10 is the fan-out signal TWCS 2d targets.

## Analysis

### Why so many SSTables

- Object/metadata TTL ≈ **30 days** (filer / retention policy; table `default_time_to_live = 0` means TTL is applied per-write or by upstream, not as table default).
- TWCS keeps roughly one SSTable set per time window for the retained horizon.
- 30d / 6h ≈ **120 windows** → 187 SSTables is consistent (plus overlap during compaction / memtable flush).
- 30d / 2d ≈ **15 windows** → expected large drop in steady-state SSTable count after windows roll and old data expires.

### Tombstones (`droppable` ≈ 0.87)

- High droppable ratio means a large share of tombstones are past `gc_grace` and eligible for purge on compaction.
- `gc_grace_seconds = 3600` (1h) is aggressive vs Cassandra defaults (10d); keep as-is unless repair/consistency policy changes.
- `unchecked_tombstone_compaction = true` already allows tombstone-focused compaction.
- **0% repaired** is a separate ops track (anti-entropy). It does **not** block the TWCS ALTER, but repair should be scheduled so deletes/TTL remain consistent across replicas.

### Compression

- Current **LZ4** stays the production default for this stage.
- Optional later tune (not required now): change `compression` class/chunk size via ALTER after measuring CPU vs disk — see “Flexible compression” below.

### Wide partitions (`/buckets/esb/...`)

- Large directory partitions increase read/compaction cost independently of TWCS window size.
- **Out of scope** for this stage: no PK redesign. Continue monitoring top partitions after the window change.

### Filer client timeouts

- Not changed in this deliverable. Filer Cassandra store already exposes connection timeout knobs in upstream SeaweedFS; customer did not request code changes.

## Migration artifacts

| File | Purpose |
|------|---------|
| [`cassandra/filemeta_twcs_2d_alter.cql`](../cassandra/filemeta_twcs_2d_alter.cql) | Apply TWCS window 2 DAYS |
| [`cassandra/filemeta_twcs_6h_rollback.cql`](../cassandra/filemeta_twcs_6h_rollback.cql) | Rollback to 6 HOURS |
| [`scripts/cassandra_filemeta_checks.sh`](../scripts/cassandra_filemeta_checks.sh) | Pre/post checklist (+ optional stand mirror smoke) |

Runbook: [05-PRODUCTION-RUNBOOKS.md](05-PRODUCTION-RUNBOOKS.md) § Cassandra filemeta TWCS.

## Expected post-ALTER behavior

1. **Immediate:** `DESCRIBE` shows `compaction_window_unit=DAYS`, `compaction_window_size=2`. Existing SSTables are not rewritten instantly.
2. **Hours–days:** new writes land in 2d windows; compaction merges within windows; SSTable count trend should fall as old 6h windows age out / are compacted.
3. **Over ~1 retention cycle (~30d):** steady-state closer to ~15 windows of retained data (order-of-magnitude; exact count depends on write rate and thresholds).
4. Watch: `nodetool compactionstats`, pending compactions, read p95/p99, droppable tombstone ratio, disk free on Cassandra nodes.

## Flexible compression (этап 3.2 — optional)

Example only — **do not** apply without change window and CPU/disk baseline:

```cql
-- OPTIONAL: evaluate after TWCS 2d is stable
ALTER TABLE seaweedfs.filemeta
WITH compression = {
  'class': 'org.apache.cassandra.io.compress.ZstdCompressor',
  'chunk_length_in_kb': '16'
};
```

Rollback to LZ4:

```cql
ALTER TABLE seaweedfs.filemeta
WITH compression = {
  'class': 'org.apache.cassandra.io.compress.LZ4Compressor',
  'chunk_length_in_kb': '16'
};
```

## Out of scope

- teye keyspaces / dual-read migration
- Automatic prod ALTER from CI/compose
- PK / directory layout changes for `esb`
- Mandatory compression change
- Changing `gc_grace_seconds` or enabling repair as part of the ALTER itself
