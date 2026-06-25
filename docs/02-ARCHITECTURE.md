# Architecture

## Production paths (customer-confirmed)

```
WRITE:  client → sideweed → S3 Gateway:8333 → filer:8888 → master → volume nodes
READ:   client → HAProxy/Varnish → S3 Gateway (not sideweed on browser read)
Snapshots: same write path; target bucket csb (prod camera snapshots still in vab)
```

**Rules:** clients never call volume nodes; sideweed balances **S3 Gateway**; direct volume access is **debug only** (`scripts/debug/`).

## Stand vs production

| Aspect | Production | Stand |
|--------|------------|-------|
| Write LB | sideweed → stor{1..3}:8333 | sideweed:8880 → s3:8333 |
| Write-health gate | not in prod env archives | `--write-health-enabled`, `/v1/write-health` |
| Read | HAProxy + Varnish + snapshot cache | HAProxy:8882 |
| Master | 3 peers | 1 |
| Volume dirs | 14 per node (`/mnt/stor1`…`stor14`) | 2 nodes × 1 dir |
| Replication | production RF | `000` (dev) |

## Buckets

| Bucket | Prod write | Prod read | TZ target |
|--------|------------|-----------|-----------|
| vab | archive + camera snapshots | yes | archive only |
| csb | not used | read-ready | camera snapshots |
| esb | events | Varnish TTL 30d | unchanged |

Stand archive bucket: `video-fragments` (not prod `vab`).

## SeaweedFS fork

- **Repo:** `github.com/troyanoff97/seaweedfs`, branch `feat/volume-disk-health-isolation`
- **Pin:** `1528e7d` (`make check-seaweedfs`)
- **Patch:** per-dir disk health, skip unhealthy dirs in assign, readonly existing volumes, `/status` DiskHealth, heartbeat on change
- **Prod example:** `weed volume -dir=/mnt/stor1,...,/mnt/stor14 -minFreeSpace=50GiB`
- **Metric:** `seaweed_volumeServer_disk_healthy{dir}`

## Cassandra (two layers)

**Filer (production):** keyspace `seaweedfs`, table `filemeta`, PK `(directory,name)`, TWCS 6h, RF=3.

**Application (teye):** separate cluster; DDL not in archives — customer must provide.

**Stand:** `video_archive.fragments`, PK `(camera_id, fragment_id)`, RF=1.

**Draft v2** (`cassandra/schema-v2.cql`): `time_bucket` + TWCS — manual apply only, not runtime.

**Load model (TZ):** ~10k cameras, 20s fragments, 3y retention → billions of rows; v1 PK hot partitions at scale.

## sideweed write gate

**Blocking probes** (affect PUT gate): `s3`, `filer`, `master`, `assign`.

**Visibility probes** (`--write-health-visibility-check`, `blocking: false` in JSON): direct volume health, e.g. `volume1=http://volume1:8080/healthz`.

| Endpoint | Role |
|----------|------|
| `GET /v1/health` | LB pool (S3 backend up) |
| `GET /v1/write-health` | Write readiness + per-probe JSON (200/503) |
| `GET /metrics` | Prometheus |

**Behavior:** first failed **blocking** round → `WRITE_DEGRADED` → PUT 503 fail-fast. Single volume down + healthy assign → **PUT 200**. All volumes down → assign fails → degraded.

**Fork:** `github.com/troyanoff97/sideweed` (submodule; volume visibility in latest commit).

## Monitoring (production)

VictoriaMetrics + Grafana + vmalert. HAProxy and weed-master already export metrics; sideweed `/metrics` is compatible. **Deploy blocked** on customer SRE.

## Stand ports

| Service | Port |
|---------|------|
| sideweed (write) | 8880 |
| haproxy (read) | 8882 |
| s3 | 8333 |
| filer | 8888 |
| cassandra | 9042 |
| volume1 / volume2 | 8080 / 8081 |
