# Debug-only tools (not production)

Production clients **never** talk to volume nodes or `master /dir/assign` directly.

## Scripts

| Script | What it does |
|--------|----------------|
| `scripts/debug/put_fragment_direct.sh` | `master /dir/assign` → direct POST to volume |
| `scripts/debug/put_to_volume1.sh` | Same, pinned to volume1 (`replication=000`, `dc1`) |
| `scripts/debug/master_assign.sh` | curl `GET /dir/assign` (master internal API) |
| `scripts/debug/volume_url.sh` | Map `volumeN:8080` → localhost for direct PUT |

Wrappers at repo root redirect to `scripts/debug/`:

- `scripts/put_fragment_direct.sh`
- `scripts/put_to_volume1.sh`

## Docker compose profile `debug`

```bash
docker compose --profile debug up -d sideweed-volumes
```

`sideweed-volumes:8884` → `volume1:8080`, `volume2:8080` (native fid GET only).

## Go client debug flag

```bash
USE_DIRECT_VOLUME_PUT=1 ./bin/fragment put file.bin camera-1
# or
./bin/fragment put --direct-volume file.bin camera-1
```

## Integration tests (debug)

```bash
RUN_DEBUG_INTEGRATION=1 go test -tags='integration debug' -v ./test/integration/ -run TestDebugAssignToVolume1
```

## Production paths (for comparison)

| Operation | Path |
|-----------|------|
| PUT | `scripts/put_fragment.sh` → sideweed → S3 |
| Snapshot PUT | `scripts/put_snapshot.sh` → bucket `csb` |
| GET | `scripts/get_fragment.sh` → HAProxy → S3 |

See [README-STAND.md](../README-STAND.md).
