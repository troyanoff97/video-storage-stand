# Production runbooks

**No production changes have been applied from this repo.** Runbooks are prepared for customer change windows.

## SeaweedFS volume rollout

```bash
git clone git@github.com:troyanoff97/seaweedfs.git
git checkout feat/volume-disk-health-isolation   # pin 1528e7d
weed volume -dir=/mnt/stor1,...,/mnt/stor14 -minFreeSpace=50GiB -mserver=... -metricsPort=9324
```

Verify: disk location logs, `seaweed_volumeServer_disk_healthy{dir}`, assign skips unhealthy dirs.

## sideweed production config

```bash
sideweed -l --json --health-path=/healthz --health-duration=3s \
  --write-health-enabled \
  --write-health-check=s3=http://stor1:8333/healthz \
  --write-health-check=filer=http://filer:8888/ \
  --write-health-check=master=http://master:9333/cluster/status \
  --write-health-check="assign=http://master:9333/dir/assign?count=1&replication=XXX|200" \
  --write-health-visibility-check=volume1=http://stor1:8080/healthz \
  --address=:9000 http://stor1:8333 http://stor2:8333 ...
```

- Upstream = **S3 Gateway**, not volume nodes  
- Visibility checks optional; must not gate PUT on single volume down  
- Separate read instance without write gate  

## Snapshot migration vab → csb (not applied)

**Current:** camera snapshots write to **vab**; **csb** read path ready (Varnish/HAProxy).

| Component | Change |
|-----------|--------|
| streamserver `bucket_name` | vab → **csb** |
| teye `camera_base_url` | `/s3/vab` → `/s3/csb` |

**Strategy:** no delete old vab objects; dual-read for legacy URLs; rollback = revert configs.

**Verify:** PUT→csb, GET via Varnish, old vab readable, no sideweed 503 spike. Stand ref: `make test-snapshot`.

## Pre-production checklist

- [ ] Write path: sideweed → S3 GW only  
- [ ] Read path: HAProxy/Varnish  
- [ ] Disk-health patch on all volume nodes  
- [ ] Write gate + visibility probes configured  
- [ ] vmalert on `sideweed_write_health_status` and `seaweed_volumeServer_disk_healthy`

## Push & release (maintainers)

**Order:** sideweed submodule commit → push sideweed remote → root submodule pointer → root push.

**Never push:** upstream `seaweedfs/seaweedfs`, `targetaidev/sideweed`.

**Pre-push suite:**

```bash
make health test test-snapshot test-range-query verify-path test-sideweed
go test ./...
bash -n scripts/chaos/*.sh scripts/disk-sim/*.sh
```

**Pins (update after each release):** SeaweedFS `1528e7d`, sideweed submodule SHA in root.

## Cassandra — data to request from customer

1. `DESCRIBE` teye DDL  
2. Query patterns (p50/p95 windows)  
3. Retention and snapshot frequency  
4. `nodetool tablestats` / compaction settings  
5. Tombstone / SSTable sizes  
6. streamserver / teye pipeline configs  
7. Migration constraints for dual-read  

**Do not** apply `cassandra/schema-v2.cql` without sign-off.

## Customer prerequisites

- Isolated volume node for bare-metal disk tests  
- teye DDL and load facts  
- Change window owner for csb migration  
- VM scrape + vmalert integration  
- Dual-read policy for legacy `vab/*.jpeg` URLs  
