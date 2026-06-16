package fragment

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// SeaweedConfig holds SeaweedFS HTTP endpoints.
type SeaweedConfig struct {
	MasterURL    string
	SideweedURL  string
	Replication  string
	DataCenter   string
	VolumeHosts  map[string]string
	HTTPClient   *http.Client
	Retry        RetryConfig
	Circuit      CircuitBreakerConfig
}

// DefaultVolumeHosts maps docker network hosts to localhost URLs.
func DefaultVolumeHosts() map[string]string {
	return map[string]string{
		"volume1:8080": "http://localhost:8080",
		"volume2:8080": "http://localhost:8081",
	}
}

type SeaweedClient struct {
	cfg      SeaweedConfig
	circuit  *masterCircuitBreaker
}

func NewSeaweedClient(cfg SeaweedConfig) *SeaweedClient {
	if cfg.Replication == "" {
		cfg.Replication = "001"
	}
	if cfg.VolumeHosts == nil {
		cfg.VolumeHosts = DefaultVolumeHosts()
	}
	if cfg.HTTPClient == nil {
		cfg.HTTPClient = &http.Client{Timeout: 2 * time.Minute}
	}
	if cfg.Retry.AssignMaxAttempts == 0 {
		cfg.Retry = defaultRetryConfig()
	}
	return &SeaweedClient{
		cfg:     cfg,
		circuit: newMasterCircuitBreaker(cfg.Circuit),
	}
}

func (c *SeaweedClient) Assign(ctx context.Context) (AssignResult, int, error) {
	if err := c.circuit.Allow(); err != nil {
		return AssignResult{}, 0, err
	}

	result, code, err := c.assignOnce(ctx)
	if err != nil {
		if code == 0 || isConnectionError(err) {
			c.circuit.OnFailure(true)
		}
		return result, code, err
	}

	c.circuit.OnSuccess()
	return result, code, nil
}

// AssignWithRetry retries assign on HTTP 406 and transient errors.
func (c *SeaweedClient) AssignWithRetry(ctx context.Context) (AssignResult, error) {
	var lastErr error
	for attempt := 1; attempt <= c.cfg.Retry.AssignMaxAttempts; attempt++ {
		result, code, err := c.Assign(ctx)
		if err == nil {
			return result, nil
		}
		lastErr = err

		retryable := false
		var assignErr *AssignError
		if errors.As(err, &assignErr) {
			retryable = assignErr.Retryable
		} else if errors.Is(err, ErrMasterCircuitOpen) {
			return AssignResult{}, err
		} else if code == 0 || isRetryableHTTP(code) {
			retryable = true
		}

		if !retryable || attempt == c.cfg.Retry.AssignMaxAttempts {
			break
		}
		if err := sleepWithBackoff(ctx, attempt, c.cfg.Retry.BaseDelay); err != nil {
			return AssignResult{}, err
		}
	}
	return AssignResult{}, lastErr
}

func (c *SeaweedClient) assignOnce(ctx context.Context) (AssignResult, int, error) {
	q := url.Values{}
	q.Set("count", "1")
	q.Set("replication", c.cfg.Replication)
	if c.cfg.DataCenter != "" {
		q.Set("dataCenter", c.cfg.DataCenter)
	}

	reqURL := strings.TrimSuffix(c.cfg.MasterURL, "/") + "/dir/assign?" + q.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return AssignResult{}, 0, err
	}

	resp, err := c.cfg.HTTPClient.Do(req)
	if err != nil {
		if isNetError(err) {
			return AssignResult{}, 0, &AssignError{
				StatusCode: 0,
				Retryable:  false,
				Message:    fmt.Sprintf("assign connection error: %v", err),
			}
		}
		return AssignResult{}, 0, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return AssignResult{}, resp.StatusCode, err
	}

	var result AssignResult
	if err := json.Unmarshal(body, &result); err != nil {
		return AssignResult{}, resp.StatusCode, fmt.Errorf("decode assign: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		msg := result.Error
		if msg == "" {
			msg = string(body)
		}
		return result, resp.StatusCode, &AssignError{
			StatusCode: resp.StatusCode,
			Retryable:  isRetryableHTTP(resp.StatusCode),
			Message:    fmt.Sprintf("assign HTTP %d: %s", resp.StatusCode, msg),
		}
	}
	if result.FID == "" {
		return result, resp.StatusCode, &AssignError{
			StatusCode: resp.StatusCode,
			Retryable:  false,
			Message:    "assign returned empty fid",
		}
	}
	return result, resp.StatusCode, nil
}

func (c *SeaweedClient) PutDirect(ctx context.Context, assign AssignResult, filename string, data []byte) (int, error) {
	return c.putDirectOnce(ctx, assign, filename, data)
}

// PutDirectWithRetry retries PUT on 5xx with a fresh assign.
func (c *SeaweedClient) PutDirectWithRetry(ctx context.Context, filename string, data []byte) (AssignResult, int, error) {
	var lastErr error
	for attempt := 1; attempt <= c.cfg.Retry.PutMaxAttempts; attempt++ {
		assign, err := c.AssignWithRetry(ctx)
		if err != nil {
			return AssignResult{}, 0, fmt.Errorf("assign for put: %w", err)
		}

		code, err := c.putDirectOnce(ctx, assign, filename, data)
		if err == nil {
			return assign, code, nil
		}
		lastErr = err

		putErr := &PutError{}
		if errors.As(err, &putErr) && putErr.Retryable && attempt < c.cfg.Retry.PutMaxAttempts {
			if sleepErr := sleepWithBackoff(ctx, attempt, c.cfg.Retry.BaseDelay); sleepErr != nil {
				return AssignResult{}, code, sleepErr
			}
			continue
		}
		return assign, code, err
	}
	return AssignResult{}, 0, lastErr
}

func (c *SeaweedClient) putDirectOnce(ctx context.Context, assign AssignResult, filename string, data []byte) (int, error) {
	volumeBase, ok := c.cfg.VolumeHosts[assign.URL]
	if !ok {
		return 0, fmt.Errorf("unknown volume URL %q", assign.URL)
	}

	var body bytes.Buffer
	w := multipart.NewWriter(&body)
	part, err := w.CreateFormFile("file", filename)
	if err != nil {
		return 0, err
	}
	if _, err := part.Write(data); err != nil {
		return 0, err
	}
	if err := w.Close(); err != nil {
		return 0, err
	}

	putURL := strings.TrimSuffix(volumeBase, "/") + "/" + assign.FID
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, putURL, &body)
	if err != nil {
		return 0, err
	}
	req.Header.Set("Content-Type", w.FormDataContentType())

	resp, err := c.cfg.HTTPClient.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	respBody, _ := io.ReadAll(resp.Body)

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		return resp.StatusCode, &PutError{
			StatusCode: resp.StatusCode,
			Retryable:  isRetryableHTTP(resp.StatusCode),
			Message:    fmt.Sprintf("PUT HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(respBody))),
		}
	}
	return resp.StatusCode, nil
}

func (c *SeaweedClient) GetViaSideweed(ctx context.Context, fid string) ([]byte, int, error) {
	return c.getOnce(ctx, fid)
}

// GetViaSideweedWithRetry retries GET on 502/503/504 and 5xx.
func (c *SeaweedClient) GetViaSideweedWithRetry(ctx context.Context, fid string) ([]byte, error) {
	var lastErr error
	for attempt := 1; attempt <= c.cfg.Retry.GetMaxAttempts; attempt++ {
		data, code, err := c.getOnce(ctx, fid)
		if err == nil {
			return data, nil
		}
		lastErr = err

		getErr := &GetError{}
		retryable := false
		if errors.As(err, &getErr) {
			retryable = getErr.Retryable
		}
		if !retryable && isRetryableGetHTTP(code) {
			retryable = true
		}
		if !retryable || attempt == c.cfg.Retry.GetMaxAttempts {
			break
		}
		if err := sleepWithBackoff(ctx, attempt, c.cfg.Retry.BaseDelay); err != nil {
			return nil, err
		}
	}
	return nil, lastErr
}

func (c *SeaweedClient) getOnce(ctx context.Context, fid string) ([]byte, int, error) {
	getURL := strings.TrimSuffix(c.cfg.SideweedURL, "/") + "/" + fid
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, getURL, nil)
	if err != nil {
		return nil, 0, err
	}

	resp, err := c.cfg.HTTPClient.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, resp.StatusCode, err
	}
	if resp.StatusCode != http.StatusOK {
		return nil, resp.StatusCode, &GetError{
			StatusCode: resp.StatusCode,
			Retryable:  isRetryableGetHTTP(resp.StatusCode),
			Message:    fmt.Sprintf("GET HTTP %d", resp.StatusCode),
		}
	}
	return data, resp.StatusCode, nil
}

func isNetError(err error) bool {
	var opErr *net.OpError
	return errors.As(err, &opErr)
}
