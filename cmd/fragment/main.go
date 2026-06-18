package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/gocql/gocql"

	"github.com/troyanoff97/video-storage-stand/pkg/fragment"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	switch os.Args[1] {
	case "put":
		os.Exit(cmdPut(os.Args[2:]))
	case "get":
		os.Exit(cmdGet(os.Args[2:]))
	default:
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, `Usage:
  fragment put <file> <camera_id> [--data-center dc1] [--direct-volume]
  fragment get <camera_id> <fragment_uuid>

Environment (production S3 path):
  SIDEWEED_URL      write entry (default http://localhost:8880)
  READ_URL          read entry via HAProxy (default http://localhost:8882)
  S3_BUCKET         (default video-fragments)
  S3_ACCESS_KEY     (default stand_access_key)
  S3_SECRET_KEY     (default stand_secret_key)
  CASSANDRA_HOSTS   (default 127.0.0.1)

Debug direct volume PUT:
  USE_DIRECT_VOLUME_PUT=1  or  fragment put --direct-volume
  MASTER_URL, REPLICATION, DATA_CENTER
`)
}

func newUploader(dataCenter string, directVolume bool) (*fragment.Uploader, error) {
	if !directVolume && os.Getenv("USE_DIRECT_VOLUME_PUT") == "1" {
		directVolume = true
	}
	cassHost := os.Getenv("CASSANDRA_HOSTS")
	if cassHost == "" {
		cassHost = "127.0.0.1"
	}
	master := envOr("MASTER_URL", "http://localhost:9333")
	sideweed := envOr("SIDEWEED_URL", "http://localhost:8880")
	readURL := envOr("READ_URL", "http://localhost:8882")

	return fragment.NewUploader(fragment.Config{
		UseDirectVolumePut: directVolume,
		Seaweed: fragment.SeaweedConfig{
			MasterURL:   master,
			SideweedURL: sideweed,
			Replication: envOr("REPLICATION", "001"),
			DataCenter:  dataCenter,
		},
		S3: fragment.S3Config{
			Bucket:           envOr("S3_BUCKET", "video-fragments"),
			AccessKey:        envOr("S3_ACCESS_KEY", "stand_access_key"),
			SecretKey:        envOr("S3_SECRET_KEY", "stand_secret_key"),
			Region:           envOr("S3_REGION", "us-east-1"),
			SideweedWriteURL: sideweed,
			ReadURL:          readURL,
		},
		Cassandra: fragment.CassandraConfig{
			Hosts:    []string{cassHost},
			Keyspace: "video_archive",
		},
	})
}

func cmdPut(args []string) int {
	fs := flag.NewFlagSet("put", flag.ExitOnError)
	dataCenter := fs.String("data-center", "", "pin assign to data center (debug direct volume only)")
	directVolume := fs.Bool("direct-volume", false, "debug: master assign + direct volume POST")
	_ = fs.Parse(args)

	if fs.NArg() != 2 {
		fmt.Fprintln(os.Stderr, "put requires <file> <camera_id>")
		return 2
	}

	data, err := os.ReadFile(fs.Arg(0))
	if err != nil {
		fmt.Fprintf(os.Stderr, "read file: %v\n", err)
		return 1
	}

	dc := *dataCenter
	if dc == "" {
		dc = os.Getenv("DATA_CENTER")
	}

	u, err := newUploader(dc, *directVolume)
	if err != nil {
		fmt.Fprintf(os.Stderr, "init: %v\n", err)
		return 1
	}
	defer u.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	frag, err := u.Put(ctx, fs.Arg(1), data)
	if err != nil {
		fmt.Fprintf(os.Stderr, "put: %v\n", err)
		return 1
	}

	fmt.Printf("SUCCESS\n")
	fmt.Printf("  camera_id:   %s\n", frag.CameraID)
	fmt.Printf("  fragment_id: %s\n", frag.FragmentID)
	fmt.Printf("  seaweed_fid: %s\n", frag.SeaweedFID)
	fmt.Printf("  size:        %d\n", frag.Size)
	return 0
}

func cmdGet(args []string) int {
	if len(args) != 2 {
		fmt.Fprintln(os.Stderr, "get requires <camera_id> <fragment_uuid>")
		return 2
	}

	fragID, err := gocql.ParseUUID(args[1])
	if err != nil {
		fmt.Fprintf(os.Stderr, "parse uuid: %v\n", err)
		return 2
	}

	u, err := newUploader("", false)
	if err != nil {
		fmt.Fprintf(os.Stderr, "init: %v\n", err)
		return 1
	}
	defer u.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	data, meta, err := u.Get(ctx, args[0], fragID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "get: %v\n", err)
		return 1
	}

	out := fmt.Sprintf("/tmp/fragment-%s.bin", fragID)
	if err := os.WriteFile(out, data, 0o644); err != nil {
		fmt.Fprintf(os.Stderr, "write: %v\n", err)
		return 1
	}

	fmt.Printf("SUCCESS\n")
	fmt.Printf("  seaweed_fid: %s\n", meta.SeaweedFID)
	fmt.Printf("  size:        %d\n", len(data))
	fmt.Printf("  output:      %s\n", out)
	return 0
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
