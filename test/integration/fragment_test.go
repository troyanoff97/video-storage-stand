//go:build integration

package integration_test

import (
	"bytes"
	"context"
	"crypto/rand"
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/troyanoff97/video-archive-stand/pkg/fragment"
)

func TestFragmentUploadDownload(t *testing.T) {
	master := env("MASTER_URL", "http://localhost:9333")
	if !reachable(master + "/cluster/status") {
		t.Skip("stand not running; start with: make up")
	}

	u, err := fragment.NewUploader(fragment.Config{
		Seaweed: fragment.SeaweedConfig{
			MasterURL:   master,
			SideweedURL: env("SIDEWEED_URL", "http://localhost:8880"),
			Replication: env("REPLICATION", "001"),
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
}

func TestAssignToVolume1DataCenter(t *testing.T) {
	master := env("MASTER_URL", "http://localhost:9333")
	if !reachable(master + "/cluster/status") {
		t.Skip("stand not running")
	}

	client := fragment.NewSeaweedClient(fragment.SeaweedConfig{
		MasterURL:   master,
		SideweedURL: env("SIDEWEED_URL", "http://localhost:8880"),
		Replication: "000",
		DataCenter:  "dc1",
	})

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	assign, code, err := client.Assign(ctx)
	if code == 406 {
		t.Skip("dc1 has no free volumes (run: make clean && make up)")
	}
	if err != nil {
		t.Fatalf("assign dc1: code=%d err=%v", code, err)
	}
	if assign.URL != "volume1:8080" {
		t.Fatalf("expected volume1:8080, got %s", assign.URL)
	}
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
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
