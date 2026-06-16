package fragment

import (
	"context"
	"fmt"
	"time"

	"github.com/gocql/gocql"
)

// Config for the combined fragment store.
type Config struct {
	Seaweed   SeaweedConfig
	Cassandra CassandraConfig
}

// Uploader implements Store using SeaweedFS + Cassandra.
type Uploader struct {
	seaweed   *SeaweedClient
	cassandra *CassandraStore
}

func NewUploader(cfg Config) (*Uploader, error) {
	cass, err := NewCassandraStore(cfg.Cassandra)
	if err != nil {
		return nil, err
	}
	return &Uploader{
		seaweed:   NewSeaweedClient(cfg.Seaweed),
		cassandra: cass,
	}, nil
}

func (u *Uploader) Close() {
	u.cassandra.Close()
}

func (u *Uploader) Put(ctx context.Context, cameraID string, data []byte) (Fragment, error) {
	assign, _, err := u.seaweed.PutDirectWithRetry(ctx, "fragment.bin", data)
	if err != nil {
		return Fragment{}, fmt.Errorf("put blob: %w", err)
	}

	frag := Fragment{
		CameraID:   cameraID,
		FragmentID: gocql.TimeUUID(),
		SeaweedFID: assign.FID,
		Size:       int64(len(data)),
		CreatedAt:  time.Now().UTC(),
	}

	if err := u.cassandra.Insert(ctx, frag); err != nil {
		return Fragment{}, fmt.Errorf("cassandra insert: %w", err)
	}

	got, err := u.seaweed.GetViaSideweedWithRetry(ctx, assign.FID)
	if err != nil {
		return Fragment{}, fmt.Errorf("verify get: %w", err)
	}
	if int64(len(got)) != frag.Size {
		return Fragment{}, fmt.Errorf("verify size mismatch: got %d want %d", len(got), frag.Size)
	}

	return frag, nil
}

func (u *Uploader) Get(ctx context.Context, cameraID string, fragmentID gocql.UUID) ([]byte, Fragment, error) {
	meta, err := u.cassandra.Select(ctx, cameraID, fragmentID)
	if err != nil {
		return nil, Fragment{}, fmt.Errorf("cassandra select: %w", err)
	}

	data, err := u.seaweed.GetViaSideweedWithRetry(ctx, meta.SeaweedFID)
	if err != nil {
		return nil, Fragment{}, fmt.Errorf("get blob: %w", err)
	}
	if int64(len(data)) != meta.Size {
		return nil, Fragment{}, fmt.Errorf("size mismatch: got %d want %d", len(data), meta.Size)
	}
	return data, meta, nil
}
