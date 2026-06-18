//go:build integration

package integration_test

import (
	"bytes"
	"context"
	"crypto/rand"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"github.com/troyanoff97/video-storage-stand/pkg/fragment"
)

func TestFragmentUploadDownload(t *testing.T) {
	master := env("MASTER_URL", "http://localhost:9333")
	if !reachable(master + "/cluster/status") {
		t.Skip("stand not running; start with: make up")
	}
	ensureStackHealthy(t)

	u, err := fragment.NewUploader(fragment.Config{
		Seaweed: fragment.SeaweedConfig{
			MasterURL:   master,
			SideweedURL: env("SIDEWEED_URL", "http://localhost:8880"),
			Replication: env("REPLICATION", "001"),
		},
		S3: fragment.S3Config{
			Bucket:           env("S3_BUCKET", "video-fragments"),
			AccessKey:        env("S3_ACCESS_KEY", "stand_access_key"),
			SecretKey:        env("S3_SECRET_KEY", "stand_secret_key"),
			Region:           env("S3_REGION", "us-east-1"),
			SideweedWriteURL: env("SIDEWEED_URL", "http://localhost:8880"),
			ReadURL:          env("READ_URL", "http://localhost:8882"),
		},
		Cassandra: fragment.CassandraConfig{
			Hosts:    []string{env("CASSANDRA_HOSTS", "127.0.0.1")},
			Keyspace: "video_archive",
		},
	})
	if err != nil {
		t.Fatalf("new uploader: %v", err)
	}
	defer u.Close()

	payload := make([]byte, 256*1024)
	if _, err := rand.Read(payload); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	cameraID := "integration-test"
	frag, err := u.Put(ctx, cameraID, payload)
	if err != nil {
		t.Fatalf("put: %v", err)
	}

	got, meta, err := u.Get(ctx, cameraID, frag.FragmentID)
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if !bytes.Equal(payload, got) {
		t.Fatalf("payload mismatch")
	}
	if meta.SeaweedFID != frag.SeaweedFID {
		t.Fatalf("fid mismatch")
	}
	if frag.SeaweedFID == "" || frag.SeaweedFID[:5] != "s3://" {
		t.Fatalf("expected s3:// object uri from production path, got %q", frag.SeaweedFID)
	}
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func projectRoot() string {
	wd, err := os.Getwd()
	if err != nil {
		return "."
	}
	return filepath.Clean(filepath.Join(wd, "..", ".."))
}

func compose(t *testing.T, args ...string) {
	t.Helper()
	cmd := exec.Command("docker", append([]string{
		"compose", "-f", "docker-compose.yml", "-f", "docker-compose.chaos.yml",
	}, args...)...)
	cmd.Dir = projectRoot()
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("docker compose %v: %v\n%s", args, err, out)
	}
}

func stopVolume2(t *testing.T) {
	t.Helper()
	compose(t, "stop", "volume2")
	time.Sleep(3 * time.Second)
}

func startVolume2() {
	cmd := exec.Command("docker", "compose", "-f", "docker-compose.yml", "-f", "docker-compose.chaos.yml", "up", "-d", "volume2")
	cmd.Dir = projectRoot()
	_ = cmd.Run()
}

func ensureStackHealthy(t *testing.T) {
	t.Helper()
	compose(t, "up", "-d", "master", "volume1", "volume2", "filer", "s3", "sideweed", "sideweed-read", "haproxy")
	time.Sleep(15 * time.Second)
}

func reachable(url string) bool {
	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return false
	}
	resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}
