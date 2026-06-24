package fragment

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/gocql/gocql"
)

// Config for the combined fragment store.
type Config struct {
	Seaweed            SeaweedConfig
	S3                 S3Config
	Cassandra          CassandraConfig
	UseDirectVolumePut bool
}

// Uploader implements Store using SeaweedFS + Cassandra.
type Uploader struct {
	seaweed   *SeaweedClient
	s3        S3Config
	cassandra *CassandraStore
	useDirect bool
}

func NewUploader(cfg Config) (*Uploader, error) {
	if cfg.S3.Bucket == "" {
		cfg.S3 = defaultS3Config()
	}
	if cfg.Seaweed.SideweedURL == "" {
		cfg.Seaweed.SideweedURL = cfg.S3.SideweedWriteURL
	}
	cass, err := NewCassandraStore(cfg.Cassandra)
	if err != nil {
		return nil, err
	}
	return &Uploader{
		seaweed:   NewSeaweedClient(cfg.Seaweed),
		s3:        cfg.S3,
		cassandra: cass,
		useDirect: cfg.UseDirectVolumePut,
	}, nil
}

func (u *Uploader) Close() {
	u.cassandra.Close()
}

func (u *Uploader) Put(ctx context.Context, cameraID string, data []byte) (Fragment, error) {
	fragID := gocql.TimeUUID()
	if u.useDirect {
		return u.putDirect(ctx, cameraID, fragID, data)
	}
	return u.putS3(ctx, cameraID, fragID, data)
}

func (u *Uploader) putS3(ctx context.Context, cameraID string, fragID gocql.UUID, data []byte) (Fragment, error) {
	key := fmt.Sprintf("%s/%s.bin", cameraID, fragID.String())
	objectURI, _, err := u.s3.PutViaSideweed(ctx, key, data)
	if err != nil {
		return Fragment{}, fmt.Errorf("put s3 object: %w", err)
	}

	frag := Fragment{
		CameraID:   cameraID,
		FragmentID: fragID,
		SeaweedFID: objectURI,
		Size:       int64(len(data)),
		CreatedAt:  time.Now().UTC(),
	}

	if err := u.cassandra.Insert(ctx, frag); err != nil {
		return Fragment{}, fmt.Errorf("cassandra insert: %w", err)
	}

	got, err := u.s3.GetViaReadPath(ctx, objectURI)
	if err != nil {
		return Fragment{}, fmt.Errorf("verify s3 get: %w", err)
	}
	if int64(len(got)) != frag.Size {
		return Fragment{}, fmt.Errorf("verify size mismatch: got %d want %d", len(got), frag.Size)
	}
	return frag, nil
}

func (u *Uploader) putDirect(ctx context.Context, cameraID string, fragID gocql.UUID, data []byte) (Fragment, error) {
	assign, _, err := u.seaweed.PutDirectWithRetry(ctx, "fragment.bin", data)
	if err != nil {
		return Fragment{}, fmt.Errorf("put blob: %w", err)
	}

	frag := Fragment{
		CameraID:   cameraID,
		FragmentID: fragID,
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

func (u *Uploader) ListFragmentsByTimeRange(ctx context.Context, cameraID string, from, to time.Time, limit int) ([]Fragment, error) {
	return u.cassandra.ListFragmentsByTimeRange(ctx, cameraID, from, to, limit)
}

func (u *Uploader) Get(ctx context.Context, cameraID string, fragmentID gocql.UUID) ([]byte, Fragment, error) {
	meta, err := u.cassandra.Select(ctx, cameraID, fragmentID)
	if err != nil {
		return nil, Fragment{}, fmt.Errorf("cassandra select: %w", err)
	}

	var data []byte
	if strings.HasPrefix(meta.SeaweedFID, "s3://") {
		data, err = u.s3.GetViaReadPath(ctx, meta.SeaweedFID)
		if err != nil {
			return nil, Fragment{}, fmt.Errorf("get s3 object: %w", err)
		}
	} else {
		data, err = u.seaweed.GetViaSideweedWithRetry(ctx, meta.SeaweedFID)
		if err != nil {
			return nil, Fragment{}, fmt.Errorf("get blob: %w", err)
		}
	}
	if int64(len(data)) != meta.Size {
		return nil, Fragment{}, fmt.Errorf("size mismatch: got %d want %d", len(data), meta.Size)
	}
	return data, meta, nil
}
