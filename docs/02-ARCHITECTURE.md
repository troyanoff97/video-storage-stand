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

- **Repo:** `github.com/troyanoff97/seaweedfs`
- **Prod/stand pin (3.80 line):** branch `feat/volume-disk-health-isolation`, pin `af88c7f` (`make check-seaweedfs`)
- **Optional 4.40 line:** branch `feat/volume-disk-health-isolation-4.40`, pin `7e3b8122f` (same disk-health / hot-disk features ported onto upstream tag `4.40`)
- **Patch:** per-dir disk health with a real create/write/fsync/remove probe, skip unhealthy dirs in assign, readonly existing volumes, `/status` DiskHealth, heartbeat on change, **hot add/remove disk dirs** via `/admin/disk/{add,remove,list}`
- **Prod example:** `weed volume -dir=/mnt/stor1,...,/mnt/stor14 -minFreeSpace=50GiB`
- **Metric:** `seaweed_volumeServer_disk_healthy{dir}`
- **Hot disk replace:** remove failed dir (`force=true` if volumes remain) → OS replace/mount → add dir; no `weed-volume` restart. Runtime set persisted to `-dir.config` (default `/var/lib/seaweedfs/volume.<ip>.<port>.disks.json`) and overrides systemd `-dir` after restart

Do **not** mix binaries from 3.80 and 4.40 lines on the same volume node without a planned upgrade. Stand default remains the 3.80 pin.

## Cassandra (two layers)

**Filer (production):** keyspace `seaweedfs`, table `filemeta`, PK `(directory,name)`, RF=3.

- **Current prod:** TWCS window **6 HOURS**, LZ4, `default_time_to_live=0`, `gc_grace_seconds=3600`, ~187 SSTables / ~6.3 GiB, droppable tombstone ratio ~0.87, 0% repaired (baseline 2026-07-31).
- **Этап 3 target:** TWCS window **2 DAYS** (manual ALTER) — fewer windows under ~30d TTL → lower read fan-out. Artifacts: [07-CASSANDRA-FILEMETA.md](07-CASSANDRA-FILEMETA.md), `cassandra/filemeta_twcs_2d_alter.cql` / rollback.
- Wide partitions under `/buckets/esb/...` observed; no PK redesign in this stage.

**Application (teye):** separate cluster — **out of scope** for stages 3–4 (customer confirmation).

**Stand:** `video_archive.fragments`, PK `(camera_id, fragment_id)`, RF=1. Optional TWCS mirror smoke: `cassandra/filemeta_twcs_2d_mirror_stand.cql` + `make cassandra-filemeta-checks STAND_MIRROR=1`.

**Draft v2** (`cassandra/schema-v2.cql`): `time_bucket` + TWCS for archive metadata experiments — manual apply only, not runtime, not `filemeta`.

**Load model (TZ):** ~10k cameras, 20s fragments, 3y retention → billions of rows; v1 PK hot partitions at scale.

## sideweed write gate

**Blocking probes** (affect PUT gate): `s3`, `filer`, `master`, `assign`.

**Multi-node OR:** same role is OR (`master1`/`master2` → at least one OK); different roles are AND (need live master **and** filer). Role = name without trailing digits (`filer-2` → `filer`).

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
