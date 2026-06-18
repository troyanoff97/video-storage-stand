# Stand testing (production-like path)

## Start

```bash
make up
make health
make test              # PUT sideweed→S3, GET HAProxy→S3
make test-go
make test-sideweed     # PUT block when master/volumes/S3 unhealthy
./scripts/verify_production_path.sh   # log proof
```

## Production PUT / GET

```bash
# Fragment write: sideweed → S3 (bucket video-fragments)
./scripts/put_fragment.sh /tmp/file.bin camera-1

# Snapshot write: same path, bucket csb
./scripts/put_snapshot.sh /tmp/snap.bin snapshot-1

# Read: HAProxy → sideweed-read → S3
./scripts/get_fragment.sh camera-1 <fragment_uuid>
```

## Acceptance tests

| Target | Path |
|--------|------|
| `make test` | Production PUT + GET |
| `make test-sideweed` | Sideweed write gate: PUT 503 on degraded cluster |
| `make chaos-multi-dir` | Disk /data1 fault via S3 PUT |
| `make chaos-matrix` | Fault matrix via S3 PUT |

Direct volume PUT is **not** used in acceptance tests.

## Debug only

See [DEBUG.md](DEBUG.md).

## Ports

| Service | Port | Role |
|---------|------|------|
| sideweed | 8880 | **write entry** |
| haproxy | 8882 | **read entry** |
| s3 | 8333 | S3 Gateway |
| filer | 8888 | filer |

Credentials: `stand_access_key` / `stand_secret_key`

## Replication

Stand uses `replication=000` so S3 writes can grow volumes on a 2-node dev stack.

See [README-STAND.md](../README-STAND.md), [TZ-DEVIATIONS.md](TZ-DEVIATIONS.md).
