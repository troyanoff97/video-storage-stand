# Production deployment (bare metal) — SeaweedFS volume node with disk-health patch

Guide for deploying the patched weed-volume on a physical or VM volume server. The stand repo is for testing; production uses the same `./seaweedfs` fork built on the target host.

## What “production deploy” means here

| Component | Stand (Docker) | Production (bare metal) |
|-----------|----------------|-------------------------|
| weed-volume | container `work2-seaweedfs:local` | native binary or systemd service |
| `-dir` | tmpfs / named volume / bind | RAID mount, e.g. `/mnt/raid/seaweed` |
| Metrics | `-metricsPort=9324` | same, scrape from Prometheus |
| Patch | `feat/volume-disk-health-isolation` | same branch in customer fork |

This does **not** include full Aziz stack (Cassandra csb/vab, sideweed PUT gate) — only the volume node with per-disk health.

## 1. Build binary on the volume server

```bash
git clone <customer-seaweedfs-fork-url> /opt/seaweedfs
cd /opt/seaweedfs
git checkout feat/volume-disk-health-isolation

cd weed
CGO_ENABLED=0 go build -o /usr/local/bin/weed .
weed version
```

Or build Docker image from `docker/seaweedfs.Dockerfile` (context `./seaweedfs`) and run with host bind-mounts.

## 2. Filesystem layout

Single directory per node (typical production):

```text
/mnt/raid/seaweed/     # -dir (RAID1/RAID10)
/mnt/raid/seaweed-idx/ # optional -dir.idx
```

Multi-directory on one node (JBOD / multiple mounts):

```bash
weed volume -dir=/mnt/disk1,/mnt/disk2 -max=8,8 ...
```

Each `-dir` is tracked independently in `/status` → `DiskHealth` and `seaweed_volumeServer_disk_healthy{dir}`.

## 3. systemd unit example

```ini
[Unit]
Description=SeaweedFS volume server (disk-health patch)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=seaweed
Group=seaweed
ExecStart=/usr/local/bin/weed volume \
  -ip=10.0.0.12 \
  -mserver=master1:9333,master2:9333 \
  -dir=/mnt/raid/seaweed \
  -max=32 \
  -dataCenter=dc1 \
  -rack=rack1 \
  -metricsPort=9324 \
  -metricsIp=0.0.0.0
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

## 4. Health and monitoring

**HTTP `/status`** (admin port, default 8080):

```bash
curl -s http://volume-host:8080/status | jq .DiskHealth
```

**Prometheus** (requires `-metricsPort`):

```bash
curl -s http://volume-host:9324/metrics | grep seaweed_volumeServer_disk_healthy
```

Alert when `seaweed_volumeServer_disk_healthy{dir="/mnt/raid/seaweed"} == 0` for > 2 minutes.

**Logs** (journald or files):

```text
disk location /mnt/disk1 marked unhealthy (io): ...
disk location /mnt/disk1 recovered and is healthy again; ...
```

## 5. Operational runbook (disk fault)

1. Disk I/O errors or full disk → location marked **unhealthy**, excluded from new writes.
2. Other `-dir` on the same node continue accepting assigns.
3. After fixing mount/space → within ~60s recovery tick, location returns **healthy**.
4. Do **not** restart the whole node for a single bad disk unless all directories are lost.

Validate locally before prod:

```bash
make chaos-multi-dir    # per-dir isolation
make chaos-recovery-disk # ro → reset → GET
```

## 6. Customer fork

Push the branch to the customer private repo manually — see [seaweedfs-customer-fork.md](seaweedfs-customer-fork.md).

## 7. Stand vs production checklist

- [ ] Branch `feat/volume-disk-health-isolation` deployed
- [ ] `-metricsPort` open to Prometheus only (firewall)
- [ ] `-dir` on durable mounts (not tmpfs)
- [ ] Alerts on `disk_healthy == 0` and `marked unhealthy` logs
- [ ] Runbook tested with `make chaos-multi-dir` on patched image
