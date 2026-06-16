package fragment

import (
	"sync"
	"time"
)

// CircuitBreakerConfig controls master assign protection.
type CircuitBreakerConfig struct {
	FailureThreshold int
	Cooldown         time.Duration
}

func defaultCircuitBreakerConfig() CircuitBreakerConfig {
	return CircuitBreakerConfig{
		FailureThreshold: 3,
		Cooldown:         10 * time.Second,
	}
}

type circuitState int

const (
	circuitClosed circuitState = iota
	circuitOpen
)

type masterCircuitBreaker struct {
	cfg       CircuitBreakerConfig
	mu        sync.Mutex
	state     circuitState
	failures  int
	openUntil time.Time
}

func newMasterCircuitBreaker(cfg CircuitBreakerConfig) *masterCircuitBreaker {
	if cfg.FailureThreshold <= 0 {
		cfg = defaultCircuitBreakerConfig()
	}
	if cfg.Cooldown <= 0 {
		cfg.Cooldown = 10 * time.Second
	}
	return &masterCircuitBreaker{cfg: cfg, state: circuitClosed}
}

func (b *masterCircuitBreaker) Allow() error {
	b.mu.Lock()
	defer b.mu.Unlock()

	if b.state == circuitOpen {
		if time.Now().Before(b.openUntil) {
			return ErrMasterCircuitOpen
		}
		b.state = circuitClosed
		b.failures = 0
	}
	return nil
}

func (b *masterCircuitBreaker) OnSuccess() {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.state = circuitClosed
	b.failures = 0
	b.openUntil = time.Time{}
}

func (b *masterCircuitBreaker) OnFailure(isConnectionError bool) {
	if !isConnectionError {
		return
	}
	b.mu.Lock()
	defer b.mu.Unlock()

	b.failures++
	if b.failures >= b.cfg.FailureThreshold {
		b.state = circuitOpen
		b.openUntil = time.Now().Add(b.cfg.Cooldown)
	}
}

func (b *masterCircuitBreaker) State() circuitState {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.state
}
