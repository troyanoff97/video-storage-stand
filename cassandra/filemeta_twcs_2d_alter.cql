-- =============================================================================
-- PRODUCTION (manual): widen TWCS window on seaweedfs.filemeta
-- 6 HOURS → 2 DAYS
-- =============================================================================
-- DO NOT apply automatically from docker-compose / CI.
-- Follow docs/05-PRODUCTION-RUNBOOKS.md (Cassandra filemeta TWCS) and
-- docs/07-CASSANDRA-FILEMETA.md. Capture baseline with
-- scripts/cassandra_filemeta_checks.sh first.
--
-- Preserves other TWCS knobs from prod DESCRIBE (2026-07-31):
--   max_threshold=32, min_threshold=4,
--   tombstone_compaction_interval=86400,
--   unchecked_tombstone_compaction=true
-- Leaves compression, gc_grace_seconds, default_time_to_live unchanged.
-- =============================================================================

ALTER TABLE seaweedfs.filemeta
WITH compaction = {
  'class': 'org.apache.cassandra.db.compaction.TimeWindowCompactionStrategy',
  'compaction_window_size': '2',
  'compaction_window_unit': 'DAYS',
  'max_threshold': '32',
  'min_threshold': '4',
  'tombstone_compaction_interval': '86400',
  'unchecked_tombstone_compaction': 'true'
};
