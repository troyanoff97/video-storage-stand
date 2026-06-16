package fragment

import (
	"time"

	"github.com/gocql/gocql"
)

// Fragment is metadata for a stored video chunk.
type Fragment struct {
	CameraID   string
	FragmentID gocql.UUID
	SeaweedFID string
	Size       int64
	CreatedAt  time.Time
}

// AssignResult is the SeaweedFS master /dir/assign response.
type AssignResult struct {
	FID       string `json:"fid"`
	URL       string `json:"url"`
	PublicURL string `json:"publicUrl"`
	Count     int    `json:"count"`
	Error     string `json:"error"`
}
