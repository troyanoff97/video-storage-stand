# Production runbooks

**No production changes have been applied from this repo.** Runbooks are prepared for customer change windows.

## SeaweedFS volume rollout

**3.80 line (current):**

```bash
git clone git@github.com:troyanoff97/seaweedfs.git
git checkout feat/volume-disk-health-isolation   # or pin af88c7f
weed volume -dir=/mnt/stor1,...,/mnt/stor14 -minFreeSpace=50GiB -mserver=... -metricsPort=9324
```

**4.40 line (optional):** branch `feat/volume-disk-health-isolation-4.40`, pin `d7f8761ec` — same disk-health / hot-disk features on upstream `4.40`. Do not mix 3.80 and 4.40 binaries on one node without a planned upgrade.

Verify: disk location logs, `seaweed_volumeServer_disk_healthy{dir}`, assign skips unhealthy dirs.

### Hot disk add/remove (no volume process restart)

HTTP admin on volume port (whitelist if configured). Changes are persisted to
`-dir.config` (default `/var/lib/seaweedfs/volume.<ip>.<port>.disks.json`) and
**override** systemd `-dir` on the next restart. Ensure the config directory is
writable (`mkdir -p /var/lib/seaweedfs`), or set `-dir.config=/path/writable/....json`.
Cannot remove the last remaining disk (add a replacement first).

Preferred: `weed shell` (same binary as volume):

```bash
weed shell -master=MASTER:9333
> lock
> volume.disk.list -node 10.0.12.21:8088
> volume.disk.remove -node 10.0.12.21:8088 -dir=/mnt/stor4 -force
> volume.disk.add -node 10.0.12.21:8088 -dir=/mnt/stor5 -max=0 -minFreeSpace=50GiB
> unlock
```

HTTP admin (equivalent):

```bash
# list
curl -fsS "http://VOLUME:8088/admin/disk/list"

# remove failed disk (force if volumes still registered)
curl -fsS -X POST "http://VOLUME:8088/admin/disk/remove" \
  --data-urlencode "dir=/mnt/stor4" --data-urlencode "force=true"

# OS: umount / replace / format / mount /mnt/stor4
# OR add a brand-new mount, e.g. /mnt/stor5 — no systemd edit required

# add disk back (or add /mnt/stor5)
curl -fsS -X POST "http://VOLUME:8088/admin/disk/add" \
  --data-urlencode "dir=/mnt/stor4" \
  --data-urlencode "max=0" \
  --data-urlencode "minFreeSpace=50GiB"
```

After `add`/`remove`, restart will keep the same disk set (no need to edit
`ExecStart -dir`). To fall back to systemd `-dir`, delete the `*.disks.json`
file and restart.

Disk health is probed every minute with a temporary 1-byte
create/write/fsync/remove operation under each registered directory, using the
`weed-volume` process identity. Permission, read-only filesystem, full disk,
and synchronous I/O failures set `SeaweedFS_volumeServer_disk_healthy` to `0`;
the probe file is removed immediately.

Helper: `scripts/volume_disk_hot_replace.sh`. Master receives updated heartbeat (`MaxVolumeCounts`, `LocationUuids`). With `replication=000`, data on a physically failed disk is not recoverable by the cluster.

## sideweed production config

```bash
sideweed -l --json --health-path=/healthz --health-duration=3s \
  --write-health-enabled \
  --write-health-check=s3=http://stor1:8333/healthz \
  --write-health-check=s3-2=http://stor2:8333/healthz \
  --write-health-check=s3-3=http://stor3:8333/healthz \
  --write-health-check=filer1=http://filer1:8888/ \
  --write-health-check=filer2=http://filer2:8888/ \
  --write-health-check=filer3=http://filer3:8888/ \
  --write-health-check=master1=http://master1:9333/cluster/status \
  --write-health-check=master2=http://master2:9333/cluster/status \
  --write-health-check=master3=http://master3:9333/cluster/status \
  --write-health-check="assign1=http://master1:9333/dir/assign?count=1&replication=XXX|200" \
  --write-health-check="assign2=http://master2:9333/dir/assign?count=1&replication=XXX|200" \
  --write-health-check="assign3=http://master3:9333/dir/assign?count=1&replication=XXX|200" \
  --address=:9000 http://stor1:8333 http://stor2:8333 http://stor3:8333
```

- Upstream = **S3 Gateway**, not volume nodes  
- Same role OR (at least one master/filer/assign/s3 OK); roles AND  
- Visibility checks optional; must not gate PUT on single volume down  
- Combined read+write instance OK (GET not blocked by write gate)  

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

**Pins (update after each release):** SeaweedFS `af88c7f`, sideweed submodule SHA in root.

## Cassandra — `seaweedfs.filemeta` TWCS 6h → 2d (этап 3)

**Scope:** SeaweedFS filer table only. **teye not in scope.**  
**Not applied from this repo.** Customer applies ALTER themselves (already done in some stressed environments; **main playbook not updated yet** — use this section + CQL as the playbook source).

Background & baseline metrics: [07-CASSANDRA-FILEMETA.md](07-CASSANDRA-FILEMETA.md).

### Pre-checks

```bash
# Print nodetool/cqlsh checklist (safe; no ALTER)
./scripts/cassandra_filemeta_checks.sh
# Or on a Cassandra node:
#   HOST=<node> ./scripts/cassandra_filemeta_checks.sh
```

Capture and save:

1. `DESCRIBE TABLE seaweedfs.filemeta;` — confirm TWCS `6` / `HOURS`
2. `nodetool tablestats seaweedfs.filemeta` — SSTable count, droppable tombstone ratio, % repaired
3. `nodetool tablehistograms seaweedfs filemeta` — read p95/p99, max SSTables
4. `nodetool compactionstats` + `tpstats` — no stuck compaction storm
5. Disk free on Cassandra data directories; note filer/error rate baseline

### Apply (one DC / limited contour first if multi-DC)

```bash
cqlsh <host> -f cassandra/filemeta_twcs_2d_alter.cql
cqlsh <host> -e "DESCRIBE TABLE seaweedfs.filemeta;" | grep compaction_window
```

Expect: `compaction_window_size: '2'`, `compaction_window_unit: 'DAYS'`.  
LZ4, `gc_grace_seconds`, and `default_time_to_live` stay unchanged.

### Post-checks (repeat over hours → days)

- SSTable count **trend** (not instant drop) toward fewer windows (~15 for ~30d TTL)
- Pending compactions not unbounded; disk headroom for compaction
- Read latency p95/p99 stable or improved vs pre-baseline
- Droppable tombstone ratio — should not worsen; reclaim as windows compact
- Filer / sideweed write-health unchanged (meta path still healthy)

### Rollback

```bash
cqlsh <host> -f cassandra/filemeta_twcs_6h_rollback.cql
```

### Ops notes (not part of ALTER)

| Topic | Action |
|-------|--------|
| `Percent repaired: 0` | Schedule repair separately; do not block TWCS on it |
| Wide `/buckets/esb/...` partitions | Monitor size; PK redesign out of this stage |
| Compression | Keep LZ4; optional later ALTER — see doc § Flexible compression |

### Stand smoke (optional)

```bash
make up && make health
make cassandra-filemeta-checks STAND_MIRROR=1
```

Creates `seaweedfs_stand.filemeta`, applies 2d window, asserts DESCRIBE. Does **not** change production or runtime `schema.cql`.

**Do not** apply `cassandra/schema-v2.cql` without sign-off (archive experiment, unrelated to `filemeta`).

## Customer prerequisites

- Fold `filemeta` TWCS 2d into **main** Cassandra/SeaweedFS playbook (CQL + this runbook; already applied ad-hoc in some envs)  
- Isolated volume node for bare-metal disk tests  
- Change window owner for csb migration  
- VM scrape + vmalert integration  
- Dual-read policy for legacy `vab/*.jpeg` URLs  
