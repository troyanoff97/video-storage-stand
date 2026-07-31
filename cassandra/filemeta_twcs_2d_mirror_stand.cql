-- =============================================================================
-- STAND ONLY: mirror table to smoke-test TWCS 2d ALTER / DESCRIBE
-- =============================================================================
-- Does NOT replace runtime video_archive.fragments (schema.cql).
-- Does NOT touch production seaweedfs.filemeta.
--
-- Manual:
--   docker compose exec -T cassandra cqlsh -f /path/to/filemeta_twcs_2d_mirror_stand.cql
-- Or via: make cassandra-filemeta-checks STAND_MIRROR=1
-- =============================================================================

CREATE KEYSPACE IF NOT EXISTS seaweedfs_stand
  WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};

CREATE TABLE IF NOT EXISTS seaweedfs_stand.filemeta (
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
  AND gc_grace_seconds = 3600;

-- Apply the same ALTER shape as production (window → 2 DAYS).
ALTER TABLE seaweedfs_stand.filemeta
WITH compaction = {
  'class': 'org.apache.cassandra.db.compaction.TimeWindowCompactionStrategy',
  'compaction_window_size': '2',
  'compaction_window_unit': 'DAYS',
  'max_threshold': '32',
  'min_threshold': '4',
  'tombstone_compaction_interval': '86400',
  'unchecked_tombstone_compaction': 'true'
};
