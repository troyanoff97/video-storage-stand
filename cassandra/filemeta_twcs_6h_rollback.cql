-- =============================================================================
-- PRODUCTION (manual): rollback TWCS window on seaweedfs.filemeta
-- 2 DAYS → 6 HOURS (pre-change baseline)
-- =============================================================================
-- Use only if post-ALTER metrics regress and ops decide to revert.
-- DO NOT apply automatically from docker-compose / CI.
-- See docs/05-PRODUCTION-RUNBOOKS.md and docs/07-CASSANDRA-FILEMETA.md.
-- =============================================================================

ALTER TABLE seaweedfs.filemeta
WITH compaction = {
  'class': 'org.apache.cassandra.db.compaction.TimeWindowCompactionStrategy',
  'compaction_window_size': '6',
  'compaction_window_unit': 'HOURS',
  'max_threshold': '32',
  'min_threshold': '4',
  'tombstone_compaction_interval': '86400',
  'unchecked_tombstone_compaction': 'true'
};
