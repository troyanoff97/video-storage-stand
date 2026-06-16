package fragment

import (
	"context"
	"errors"
	"net"
	"time"
)

// RetryConfig controls client retry behaviour.
type RetryConfig struct {
	AssignMaxAttempts int
	PutMaxAttempts    int
	GetMaxAttempts    int
	BaseDelay         time.Duration
}

func defaultRetryConfig() RetryConfig {
	return RetryConfig{
		AssignMaxAttempts: 3,
		PutMaxAttempts:    2,
		GetMaxAttempts:    3,
		BaseDelay:         500 * time.Millisecond,
	}
}

func isConnectionError(err error) bool {
	if err == nil {
		return false
	}
	var netErr net.Error
	if errors.As(err, &netErr) {
		return true
	}
	return errors.Is(err, ErrMasterUnavailable)
}

func sleepWithBackoff(ctx context.Context, attempt int, base time.Duration) error {
	delay := base * time.Duration(1<<(attempt-1))
	if delay > 5*time.Second {
		delay = 5 * time.Second
	}
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

func retryDelay(attempt int, base time.Duration) time.Duration {
	delay := base * time.Duration(1<<(attempt-1))
	if delay > 5*time.Second {
		return 5 * time.Second
	}
	return delay
}
