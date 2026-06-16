CREATE KEYSPACE IF NOT EXISTS video_archive
  WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};

CREATE TABLE IF NOT EXISTS video_archive.fragments (
  camera_id text,
  fragment_id timeuuid,
  seaweed_fid text,
  size bigint,
  created_at timestamp,
  PRIMARY KEY (camera_id, fragment_id)
) WITH CLUSTERING ORDER BY (fragment_id DESC);
