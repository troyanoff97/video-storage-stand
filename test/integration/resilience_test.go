//go:build integration

package integration_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/troyanoff97/video-archive-stand/pkg/fragment"
)

func TestMasterCircuitBreakerIntegration(t *testing.T) {
	master := env("MASTER_URL", "http://localhost:9333")
	if !reachable(master + "/cluster/status") {
		t.Skip("stand not running; start with: make up")
	}

	// Unreachable master — circuit opens after repeated connection failures.
	client := fragment.NewSeaweedClient(fragment.SeaweedConfig{
		MasterURL:   "http://127.0.0.1:1",
		SideweedURL: env("SIDEWEED_URL", "http://localhost:8880"),
		Replication: "000",
		Circuit: fragment.CircuitBreakerConfig{
			FailureThreshold: 2,
			Cooldown:         100 * time.Millisecond,
		},
		Retry: fragment.RetryConfig{
			AssignMaxAttempts: 1,
			BaseDelay:         10 * time.Millisecond,
		},
	})

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	for i := 0; i < 2; i++ {
		_, _, _ = client.Assign(ctx)
	}

	_, _, err := client.Assign(ctx)
	if !errors.Is(err, fragment.ErrMasterCircuitOpen) {
		t.Fatalf("expected circuit open, got %v", err)
	}
}

func TestAssignWithRetryLive(t *testing.T) {
	master := env("MASTER_URL", "http://localhost:9333")
	if !reachable(master + "/cluster/status") {
		t.Skip("stand not running")
	}

	client := fragment.NewSeaweedClient(fragment.SeaweedConfig{
		MasterURL:   master,
		SideweedURL: env("SIDEWEED_URL", "http://localhost:8880"),
		Replication: "001",
		Retry: fragment.RetryConfig{
			AssignMaxAttempts: 3,
			BaseDelay:         100 * time.Millisecond,
		},
	})

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	assign, err := client.AssignWithRetry(ctx)
	if err != nil {
		t.Fatalf("assign with retry: %v", err)
	}
	if assign.URL != "volume1:8080" && assign.URL != "volume2:8080" {
		t.Fatalf("unexpected assign url: %s", assign.URL)
	}
}
