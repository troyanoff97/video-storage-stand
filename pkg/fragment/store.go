package fragment

import (
	"context"

	"github.com/gocql/gocql"
)

// Store uploads and retrieves video fragments (blob + metadata).
type Store interface {
	Put(ctx context.Context, cameraID string, data []byte) (Fragment, error)
	Get(ctx context.Context, cameraID string, fragmentID gocql.UUID) ([]byte, Fragment, error)
}
