//go:build integration && debug

package integration_test

import (
	"context"
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/troyanoff97/video-archive-stand/pkg/fragment"
)

// TestDebugAssignToVolume1 exercises master /dir/assign directly (not production path).
func TestDebugAssignToVolume1(t *testing.T) {
	master := env("MASTER_URL", "http://localhost:9333")
	if !reachable(master + "/cluster/status") {
		t.Skip("stand not running")
	}

	stopVolume2(t)
	t.Cleanup(func() {
		startVolume2()
		ensureStackHealthy(t)
	})

	compose(t, "restart", "volume1")
	time.Sleep(12 * time.Second)

	client := fragment.NewSeaweedClient(fragment.SeaweedConfig{
		MasterURL:   master,
		Replication: "000",
		DataCenter:  "dc1",
	})

	deadline := time.Now().Add(90 * time.Second)
	var lastCode int
	var lastErr error
	for attempt := 0; time.Now().Before(deadline); attempt++ {
		if attempt == 8 {
			compose(t, "restart", "volume1")
			time.Sleep(10 * time.Second)
		}
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		assign, code, err := client.Assign(ctx)
		cancel()
		lastCode, lastErr = code, err
		if err == nil && code == http.StatusOK && assign.URL == "volume1:8080" {
			return
		}
		time.Sleep(2 * time.Second)
	}
	t.Fatalf("debug assign to volume1 failed: code=%d err=%v", lastCode, lastErr)
}

func TestDebugAssignWithRetryLive(t *testing.T) {
	master := env("MASTER_URL", "http://localhost:9333")
	if !reachable(master + "/cluster/status") {
		t.Skip("stand not running")
	}
	ensureStackHealthy(t)

	client := fragment.NewSeaweedClient(fragment.SeaweedConfig{
		MasterURL:   master,
		Replication: "000",
		Retry: fragment.RetryConfig{
			AssignMaxAttempts: 5,
			BaseDelay:         200 * time.Millisecond,
		},
	})

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	assign, err := client.AssignWithRetry(ctx)
	if err != nil {
		t.Fatalf("assign with retry: %v", err)
	}
	if assign.URL != "volume1:8080" && assign.URL != "volume2:8080" {
		t.Fatalf("unexpected assign url: %s", assign.URL)
	}
}

func init() {
	if os.Getenv("RUN_DEBUG_INTEGRATION") != "1" {
		// Tests in this file only run with: go test -tags='integration debug' and RUN_DEBUG_INTEGRATION=1
	}
}
