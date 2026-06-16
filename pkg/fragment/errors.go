package fragment

import "errors"

var (
	// ErrMasterUnavailable is returned when the master cannot be reached.
	ErrMasterUnavailable = errors.New("seaweed master unavailable")

	// ErrMasterCircuitOpen is returned when the master circuit breaker is open.
	ErrMasterCircuitOpen = errors.New("seaweed master circuit breaker open")

	// ErrNoWritableVolumes is returned when assign returns HTTP 406.
	ErrNoWritableVolumes = errors.New("no writable seaweed volumes")

	// ErrAssignFailed is returned for non-retryable assign failures.
	ErrAssignFailed = errors.New("seaweed assign failed")
)

// AssignError wraps assign HTTP failures with retry hints.
type AssignError struct {
	StatusCode int
	Retryable  bool
	Message    string
}

func (e *AssignError) Error() string {
	return e.Message
}

func (e *AssignError) Unwrap() error {
	switch {
	case e.StatusCode == 406:
		return ErrNoWritableVolumes
	case e.StatusCode == 0:
		return ErrMasterUnavailable
	default:
		return ErrAssignFailed
	}
}

// PutError wraps PUT failures.
type PutError struct {
	StatusCode int
	Retryable  bool
	Message    string
}

func (e *PutError) Error() string {
	return e.Message
}

// GetError wraps GET failures via sideweed.
type GetError struct {
	StatusCode int
	Retryable  bool
	Message    string
}

func (e *GetError) Error() string {
	return e.Message
}

func isRetryableHTTP(code int) bool {
	return code == 406 || code == 429 || code >= 500
}

func isRetryableGetHTTP(code int) bool {
	return code == 502 || code == 503 || code == 504 || code >= 500
}
