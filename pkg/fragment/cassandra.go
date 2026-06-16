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
