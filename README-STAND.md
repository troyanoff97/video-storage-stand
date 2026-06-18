# Локальный стенд: production-like SeaweedFS + sideweed + S3

## Architecture (confirmed by customer)

```
WRITE:
  client → sideweed:8880 → S3 Gateway:8333 → filer:8888 → master → volume nodes

READ:
  client → HAProxy:8882 → sideweed-read → S3 Gateway:8333
  (production may also use sideweed directly for read)

Snapshots: same write path, bucket csb
```

**Production rules:**
- Clients never talk to volume nodes
- sideweed balances **S3 Gateway**, not volumes
- HAProxy/Varnish = read only
- Direct volume access = **debug only** → [docs/DEBUG.md](docs/DEBUG.md)
- Write sideweed blocks PUT when SeaweedFS write path is unhealthy → [docs/sideweed-health.md](docs/sideweed-health.md)

## Quick start

```bash
git submodule update --init --recursive
make up && make health && make test
./scripts/verify_production_path.sh
```

## Ports

| Service | Port | Role |
|---------|------|------|
| sideweed | 8880 | production write |
| haproxy | 8882 | production read |
| s3 | 8333 | S3 Gateway |
| filer | 8888 | filer |
| master | 9333 | topology (internal) |
| volume1/2 | 8080/8081 | blobs (internal) |
| cassandra | 9042 | stand fragment index |

## Commands

```bash
# Production PUT (fragments)
./scripts/put_fragment.sh /tmp/file.bin camera-1

# Production PUT (snapshots → bucket csb)
./scripts/put_snapshot.sh /tmp/snap.bin snap-1

# Production GET
./scripts/get_fragment.sh camera-1 <uuid>

# Debug only
./scripts/debug/put_fragment_direct.sh /tmp/file.bin camera-debug
```

## Makefile

| Target | Description |
|--------|-------------|
| `make test` | Production PUT + GET smoke |
| `make test-sideweed` | Sideweed write degradation gate |
| `make chaos-multi-dir` | Disk health via S3 path |
| `make chaos-matrix` | Fault matrix via S3 path |
| `make put-v1` | **Debug** — redirects to `scripts/debug/put_to_volume1.sh` |

## Docs

- [STAND-TESTING.md](docs/STAND-TESTING.md)
- [TZ-DEVIATIONS.md](docs/TZ-DEVIATIONS.md)
- [PRODUCTION-DEPLOY.md](docs/PRODUCTION-DEPLOY.md)
- [DEBUG.md](docs/DEBUG.md)
- [sideweed-health.md](docs/sideweed-health.md)
- [seaweedfs-disk-health.md](docs/seaweedfs-disk-health.md)
