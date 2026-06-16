package fragment

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
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
	DataCenter   string // optional: dc1, dc2 — pin assign to a volume node
	VolumeHosts  map[string]string
	HTTPClient   *http.Client
}

// DefaultVolumeHosts maps docker network hosts to localhost URLs.
func DefaultVolumeHosts() map[string]string {
	return map[string]string{
		"volume1:8080": "http://localhost:8080",
		"volume2:8080": "http://localhost:8081",
	}
}

type SeaweedClient struct {
	cfg SeaweedConfig
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
	return &SeaweedClient{cfg: cfg}
}

func (c *SeaweedClient) Assign(ctx context.Context) (AssignResult, int, error) {
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
		if result.Error != "" {
			return result, resp.StatusCode, fmt.Errorf("assign HTTP %d: %s", resp.StatusCode, result.Error)
		}
		return result, resp.StatusCode, fmt.Errorf("assign HTTP %d: %s", resp.StatusCode, string(body))
	}
	if result.FID == "" {
		return result, resp.StatusCode, fmt.Errorf("assign returned empty fid")
	}
	return result, resp.StatusCode, nil
}

func (c *SeaweedClient) PutDirect(ctx context.Context, assign AssignResult, filename string, data []byte) (int, error) {
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
	_, _ = io.Copy(io.Discard, resp.Body)

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		return resp.StatusCode, fmt.Errorf("PUT HTTP %d", resp.StatusCode)
	}
	return resp.StatusCode, nil
}

func (c *SeaweedClient) GetViaSideweed(ctx context.Context, fid string) ([]byte, int, error) {
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
		return nil, resp.StatusCode, fmt.Errorf("GET HTTP %d", resp.StatusCode)
	}
	return data, resp.StatusCode, nil
}
