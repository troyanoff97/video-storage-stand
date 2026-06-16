package fragment

import (
	"errors"
	"net"
	"testing"
	"time"
)

func TestMasterCircuitBreakerOpensAfterFailures(t *testing.T) {
	cb := newMasterCircuitBreaker(CircuitBreakerConfig{
		FailureThreshold: 2,
		Cooldown:         50 * time.Millisecond,
	})

	cb.OnFailure(true)
	if err := cb.Allow(); err != nil {
		t.Fatalf("expected allow after 1 failure, got %v", err)
	}

	cb.OnFailure(true)
	if err := cb.Allow(); err != ErrMasterCircuitOpen {
		t.Fatalf("expected circuit open, got %v", err)
	}

	time.Sleep(60 * time.Millisecond)
	if err := cb.Allow(); err != nil {
		t.Fatalf("expected half-open allow, got %v", err)
	}

	cb.OnSuccess()
	if cb.State() != circuitClosed {
		t.Fatalf("expected closed after success")
	}
}

func TestAssignErrorRetryable406(t *testing.T) {
	err := &AssignError{StatusCode: 406, Retryable: true, Message: "no volumes"}
	if !errors.Is(err, ErrNoWritableVolumes) {
		t.Fatalf("expected ErrNoWritableVolumes")
	}
	if !isRetryableHTTP(406) {
		t.Fatal("406 should be retryable")
	}
}

func TestIsConnectionError(t *testing.T) {
	err := &net.OpError{Op: "dial", Err: errors.New("connection refused")}
	if !isConnectionError(err) {
		t.Fatal("OpError should be connection error")
	}
}

func TestRetryDelayBackoff(t *testing.T) {
	if retryDelay(1, 500*time.Millisecond) != 500*time.Millisecond {
		t.Fatal("attempt 1 delay")
	}
	if retryDelay(3, 500*time.Millisecond) != 2*time.Second {
		t.Fatal("attempt 3 delay")
	}
	if retryDelay(10, 500*time.Millisecond) != 5*time.Second {
		t.Fatal("delay cap")
	}
}
