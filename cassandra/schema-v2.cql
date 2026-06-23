-- =============================================================================
-- EXPERIMENTAL Cassandra schema v2 (stand repo draft)
-- =============================================================================
-- NOT applied automatically by docker-compose or cql-init.
-- Runtime stand still uses cassandra/schema.cql → table `fragments` only.
-- Do NOT apply to production without customer DDL review and metrics validation.
-- See: docs/CASSANDRA-OPTIMIZATION.md, docs/CASSANDRA-SCHEMA-V2.md
--
-- Manual apply (optional, dev only):
--   docker compose exec -T cassandra cqlsh -f /path/mounted/schema-v2.cql
-- =============================================================================

-- Keyspace: same name as v1 for migration experiments.
-- Dev stand: SimpleStrategy RF=1.
-- Production MUST use NetworkTopologyStrategy with RF per datacenter (not defined here).
CREATE KEYSPACE IF NOT EXISTS video_archive
  WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};

-- -----------------------------------------------------------------------------
-- video_fragments_v2 — metadata for video archive fragments (ТЗ §5.1 archive)
-- -----------------------------------------------------------------------------
-- Partition (camera_id, time_bucket) limits wide partitions vs v1 (camera_id only).
-- time_bucket: calendar day (date) or YYYY-MM-DD text; choose one convention in app.
-- bucket: production archive = `vab`; stand may use `video-fragments` during transition.
-- object_uri example: s3://vab/{camera_id}/{fragment_id}.bin
--                      or s3://video-fragments/... (legacy stand)
--
-- Dual-read (future): if row missing here, fall back to legacy `fragments` table.
-- Old schema remains: video_archive.fragments (camera_id, fragment_id).
CREATE TABLE IF NOT EXISTS video_archive.video_fragments_v2 (
  camera_id text,
  time_bucket date,
  fragment_start timestamp,
  fragment_id timeuuid,
  bucket text,
  object_key text,
  object_uri text,
  size bigint,
  created_at timestamp,
  schema_version int,
  PRIMARY KEY ((camera_id, time_bucket), fragment_start, fragment_id)
) WITH CLUSTERING ORDER BY (fragment_start DESC, fragment_id DESC)
  AND comment = 'Experimental v2 archive metadata; TWCS dev defaults — validate for production'
  AND compaction = {
    'class': 'TimeWindowCompactionStrategy',
    'compaction_window_unit': 'DAYS',
    'compaction_window_size': '1',
    'max_threshold': '32',
    'min_threshold': '4'
  };
-- Production TWCS window/size MUST be tuned from nodetool tablestats / write rate.
-- Optional TTL (not set): e.g. default_time_to_live = 94608000 for ~3y after approval.

-- -----------------------------------------------------------------------------
-- snapshots_v2 — metadata for snapshots (ТЗ §5.1 csb bucket)
-- -----------------------------------------------------------------------------
-- bucket MUST be `csb` for production snapshots.
-- PK (camera_id, time_bucket) supports list-by-camera + time range within buckets.
-- Alternative if production only does point lookup by snapshot_id:
--   consider PK (snapshot_id) or secondary lookup table — depends on customer query pattern.
--
-- Dual-read (future): legacy snapshots may still live in `fragments` with snapshot_id as camera_id.
CREATE TABLE IF NOT EXISTS video_archive.snapshots_v2 (
  camera_id text,
  time_bucket date,
  snapshot_time timestamp,
  snapshot_id timeuuid,
  bucket text,
  object_key text,
  object_uri text,
  size bigint,
  created_at timestamp,
  schema_version int,
  PRIMARY KEY ((camera_id, time_bucket), snapshot_time, snapshot_id)
) WITH CLUSTERING ORDER BY (snapshot_time DESC, snapshot_id DESC)
  AND comment = 'Experimental v2 snapshot metadata; bucket=csb; compaction TBD from query pattern'
  AND compaction = {
    'class': 'TimeWindowCompactionStrategy',
    'compaction_window_unit': 'DAYS',
    'compaction_window_size': '7',
    'max_threshold': '32',
    'min_threshold': '4'
  };
-- Alternative for heavy point-read workloads: LeveledCompactionStrategy (LCS) — evaluate with customer.
-- LCS example (NOT applied):
--   AND compaction = {'class': 'LeveledCompactionStrategy'}

-- -----------------------------------------------------------------------------
-- Compatibility notes (no extra table in this draft)
-- -----------------------------------------------------------------------------
-- v1 runtime:  video_archive.fragments
-- v2 proposal: video_fragments_v2 + snapshots_v2
-- Migration: new writes → v2; reads try v2 then v1; backfill job optional (see design doc §6).
