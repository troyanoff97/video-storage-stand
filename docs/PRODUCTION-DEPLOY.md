# Production deployment

Architecture confirmed by customer:

```
WRITE:  client → sideweed → S3 Gateway → filer/master → volume nodes
READ:   client → sideweed  OR  HAProxy/Varnish → S3 Gateway
```

Clients **never** call volume nodes directly in production.

## Stack components

| Component | Role |
|-----------|------|
| **sideweed** | LB for S3 Gateway endpoints (write + optional read) |
| **SeaweedFS S3 Gateway** | S3 API; talks to filer |
| **SeaweedFS filer** | Metadata; assigns chunks via master |
| **SeaweedFS master** | Topology, volume assign |
| **SeaweedFS volume** | Blob storage (`-dir` per disk) |
| **HAProxy / Varnish** | Read path only (not write) |
| **Cassandra** | Application metadata (production: via filer integration) |

## Buckets

| Bucket | Content |
|--------|---------|
| `video-fragments` (or app-specific) | Video fragments |
| `csb` | Snapshots |

Stand: `scripts/put_fragment.sh` (fragments), `scripts/put_snapshot.sh` (csb).

## Volume node (disk-health patch)

Branch: `feat/volume-disk-health-isolation` in customer SeaweedFS fork.

```bash
weed volume -dir=/mnt/disk1,/mnt/disk2 -max=32,32 -mserver=... -metricsPort=9324
```

On unhealthy dir:
- Existing volumes → readonly (heartbeat to master)
- Master stops assign on those volume IDs
- New growth only on healthy dirs (`FindFreeLocation`)

Monitor: `/status` → `DiskHealth`, `ReadOnlyVolumeIds`; metric `seaweed_volumeServer_disk_healthy{dir}`.

## Sideweed configuration

```bash
sideweed -l --json --health-path=/healthz --health-duration=3s \
  --address=:8880 http://s3-gw-1:8333 http://s3-gw-2:8333
```

- Health path must return HTTP 200 (`/healthz` on SeaweedFS S3)
- Only `http://` upstreams supported
- No request-level retry; failed proxy marks backend DOWN

Read path (example):

```text
HAProxy → sideweed-read → S3 Gateway pool
```

## Validate before production

On patched image / stand:

```bash
make up
make test                    # PUT sideweed→S3, GET HAProxy→S3
./scripts/verify_production_path.sh
make chaos-multi-dir         # per-dir disk health via S3 path
```

Debug volume tests: [DEBUG.md](DEBUG.md) only.

## Stand vs production checklist

- [ ] sideweed upstream = S3 Gateway (not volume)
- [ ] Write path does not expose volume ports to clients
- [ ] Read path via HAProxy/Varnish → S3
- [ ] Snapshots use bucket `csb`
- [ ] Disk-health patch deployed on volume nodes
- [ ] Alerts on `disk_healthy == 0`

See also [seaweedfs-disk-health.md](seaweedfs-disk-health.md), [seaweedfs-customer-fork.md](seaweedfs-customer-fork.md).
