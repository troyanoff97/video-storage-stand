package fragment

import (
	"context"
	"fmt"
	"time"

	"github.com/gocql/gocql"
)

// CassandraConfig for fragment metadata.
type CassandraConfig struct {
	Hosts    []string
	Keyspace string
}

type CassandraStore struct {
	session *gocql.Session
}

func NewCassandraStore(cfg CassandraConfig) (*CassandraStore, error) {
	if cfg.Keyspace == "" {
		cfg.Keyspace = "video_archive"
	}
	cluster := gocql.NewCluster(cfg.Hosts...)
	cluster.Keyspace = cfg.Keyspace
	cluster.Consistency = gocql.Quorum
	cluster.Timeout = 10 * time.Second

	session, err := cluster.CreateSession()
	if err != nil {
		return nil, fmt.Errorf("cassandra session: %w", err)
	}
	return &CassandraStore{session: session}, nil
}

func (s *CassandraStore) Close() {
	if s.session != nil {
		s.session.Close()
	}
}

func (s *CassandraStore) Insert(ctx context.Context, f Fragment) error {
	q := `INSERT INTO fragments (camera_id, fragment_id, seaweed_fid, size, created_at)
	      VALUES (?, ?, ?, ?, ?)`
	return s.session.Query(q, f.CameraID, f.FragmentID, f.SeaweedFID, f.Size, f.CreatedAt).
		WithContext(ctx).Exec()
}

func (s *CassandraStore) Select(ctx context.Context, cameraID string, fragmentID gocql.UUID) (Fragment, error) {
	q := `SELECT seaweed_fid, size, created_at FROM fragments
	      WHERE camera_id = ? AND fragment_id = ?`
	var f Fragment
	f.CameraID = cameraID
	f.FragmentID = fragmentID
	if err := s.session.Query(q, cameraID, fragmentID).WithContext(ctx).
		Scan(&f.SeaweedFID, &f.Size, &f.CreatedAt); err != nil {
		return Fragment{}, err
	}
	return f, nil
}

// ListFragmentsByTimeRange returns fragments for camera_id with fragment_id (timeuuid) in [from, to].
// Uses MinTimeUUID/MaxTimeUUID bounds; table clusters by fragment_id DESC.
func (s *CassandraStore) ListFragmentsByTimeRange(ctx context.Context, cameraID string, from, to time.Time, limit int) ([]Fragment, error) {
	if from.After(to) {
		return nil, fmt.Errorf("from time must not be after to time")
	}
	if limit <= 0 {
		limit = 100
	}

	minID := gocql.MinTimeUUID(from.UTC())
	maxID := gocql.MaxTimeUUID(to.UTC())

	q := `SELECT fragment_id, seaweed_fid, size, created_at FROM fragments
	      WHERE camera_id = ? AND fragment_id >= ? AND fragment_id <= ?
	      LIMIT ?`

	iter := s.session.Query(q, cameraID, minID, maxID, limit).WithContext(ctx).Iter()

	var out []Fragment
	var (
		fragID     gocql.UUID
		seaweedFID string
		size       int64
		createdAt  time.Time
	)
	for iter.Scan(&fragID, &seaweedFID, &size, &createdAt) {
		out = append(out, Fragment{
			CameraID:   cameraID,
			FragmentID: fragID,
			SeaweedFID: seaweedFID,
			Size:       size,
			CreatedAt:  createdAt,
		})
	}
	if err := iter.Close(); err != nil {
		return nil, fmt.Errorf("list fragments: %w", err)
	}
	return out, nil
}
