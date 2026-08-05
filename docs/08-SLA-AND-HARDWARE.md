# SLA, autonomy, and hardware (этап 4)

**Status:** working targets based on observed stand/prod metrics. Customer confirmed **no formal SLA** — use the numbers below as operational acceptance indicators until a contract SLA exists.

Related: [07-CASSANDRA-FILEMETA.md](07-CASSANDRA-FILEMETA.md), [04-OPERATIONS.md](04-OPERATIONS.md), [05-PRODUCTION-RUNBOOKS.md](05-PRODUCTION-RUNBOOKS.md).

## SLA indicators (working / no formal contract)

Customer (2026-07-31): formal latency/uptime SLA **does not exist**. The table below is the deliverable baseline for dashboards and ops escalation.

### Availability

| Component | Working target | Measurement |
|-----------|-----------------|-------------|
| Write path (sideweed gate) | ≥ 99.5% time `write_health_status==1` over 30d | `sideweed_write_health_status` |
| Volume process | Process up; `/healthz` OK | systemd + volume `:healthz` (liveness only) |
| Per-disk writable | Unhealthy dirs skipped; cluster still accepts writes if other dirs OK | `seaweed_volumeServer_disk_healthy{dir}` |
| Filer / S3 GW | In write-gate probes; fail-fast PUT 503 when degraded | sideweed blocking probes |
| Cassandra (filer meta) | Cluster accepts reads/writes; no sustained unavailable exceptions | client errors + `nodetool status` |

**Note:** volume `/healthz` ≠ per-disk health. A hung `statfs` on one mount can stall UI while process is “up”.

### Latency

| Path | Working target | Baseline / source |
|------|----------|-------------------|
| Cassandra `filemeta` local read p99 | < 5 ms steady; investigate if sustained > 10 ms or SSTables-per-read rising | prod histograms ~0.9 ms p99 (2026-07-31) |
| Cassandra `filemeta` local write p99 | < 1 ms | ~50 µs p99 observed |
| sideweed PUT fail-fast when degraded | < 100 ms reject (no long backend hang) | write gate design |
| Volume assign when disks healthy | no multi-second stall on healthy dirs | disk probe + skip unhealthy |

### Disk / metadata health

| Signal | Proposed ops response |
|--------|----------------------|
| `disk_healthy==0` | Page; hot remove/replace disk; do not restart whole node unless needed |
| SSTable count on `filemeta` after TWCS 2d | Trend down over days; escalate if still climbing after 7d with pending compaction backlog |
| Droppable tombstone ratio | Expect decline after TWCS + compaction; repair track separate if 0% repaired persists |
| sideweed `WRITE_DEGRADED` | On-call; check master/filer/assign/S3 probes |

## Autonomous operations (build / update / diagnose)

### Build SeaweedFS customer fork

**3.80 line (current stand / prod pin):**

```bash
git clone git@github.com:troyanoff97/seaweedfs.git
cd seaweedfs
git checkout feat/volume-disk-health-isolation
# pin used by stand: af88c7f — prefer exact SHA for prod builds
git checkout af88c7f
# Dependencies: Go toolchain required by SeaweedFS Makefile; see fork README / go.mod
make install   # or project-standard go build → weed
```

**4.40 line (optional upgrade path):**

```bash
git clone git@github.com:troyanoff97/seaweedfs.git
cd seaweedfs
git checkout feat/volume-disk-health-isolation-4.40
# pin: d7f8761ec (disk-health + filer Cassandra fail-fast timeouts on 4.40)
git checkout d7f8761ec
make install
```

Stand pin check (`make check-seaweedfs`) still expects the **3.80** pin unless you change `SEAWEEDFS_REQUIRED_COMMIT*`. Source: `github.com/troyanoff97/seaweedfs` (+ stand docs/scripts in this repo).

**Filer `[cassandra]` (stage recommendation after redis→cassandra migration):** set `connection_timeout_millisecond = 5000`–`10000` (was 60000). Optional: `connect_timeout_millisecond = 5000`. Filer `LimitNOFILE=16384` is much lower than volume — long meta waits amplify FD pressure on filer.

### Update volume nodes (disk-health + hot disk API)

1. Build/install `weed` binary at agreed SHA.
2. Ensure `ExecStart` keeps full flags (`-port`, `-max`, `-mserver`, `-minFreeSpace`, …).
3. Add **only** `-dir.config=/opt/seaweedfs/volume/disks.json` (or writable path); `mkdir -p` parent dir.
4. Restart volume unit once for binary upgrade; afterward disk add/remove should not need restart.
5. Verify: `volume.disk.list`, metric `seaweed_volumeServer_disk_healthy`, probe logs on chown/RO fault.

### sideweed

- Submodule / fork: `github.com/troyanoff97/sideweed`
- Config: write-health checks to S3 GW + filer + master + assign (see runbook).
- Health: `GET /v1/write-health` on sideweed port (e.g. `:8880` / prod `:9000`) — **not** on volume `:8088`.

### Cassandra `filemeta`

- Pre/post: `scripts/cassandra_filemeta_checks.sh`
- ALTER: `cassandra/filemeta_twcs_2d_alter.cql` — **customer-applied** (already done in some stressed envs; fold into main playbook)
- Rollback: `cassandra/filemeta_twcs_6h_rollback.cql`
- Analysis: [07-CASSANDRA-FILEMETA.md](07-CASSANDRA-FILEMETA.md)

### Incident bundle

```bash
bash scripts/customer/collect_seaweedfs_incident_bundle.sh
```

### Common diagnostics

| Symptom | Check |
|---------|--------|
| Free=-447 / wrong port on master UI | `ExecStart` missing `-port`/`-max`; defaults 8080 / Max=32 |
| `/v1/write-health` 400 on `:8088` | Wrong service — use sideweed |
| Stale Pushgateway series | DELETE old `job`/`instance` after port change |
| Volume UI hang | Blocking `statfs` on bad mount; check mounts/dmesg |
| Disk `Healthy=false` | Probe create/write/fsync failed (perms, RO, full, I/O) |
| Many `filemeta` SSTables | TWCS window vs TTL; see stage-3 doc |

## Hardware — minimum vs recommended

Assumes production-like roles split (master / volume / filer+S3 / Cassandra / sideweed). Scale disks and Cassandra nodes to camera count and retention.

### Volume node (data)

| | Minimum | Recommended |
|--|---------|-------------|
| CPU | 8 cores | 16+ cores |
| RAM | 32 GiB | 64 GiB |
| OS | Linux x86_64 (systemd) | Same; match customer prod base image |
| Data disks | Multiple independent mounts (`/mnt/stor*`); capacity for RF and retention | Same; leave headroom ≥ `minFreeSpace` (e.g. 50 GiB) per dir |
| OS disk | 50 GiB SSD | 100 GiB SSD |
| Network | 10 GbE | 25 GbE if multi-node heavy ingest |
| Notes | One failed disk must not take down process (fork behavior) | Hot-spare mount capacity for replace-without-restart |

### Master

| | Minimum | Recommended |
|--|---------|-------------|
| CPU | 4 cores | 8 cores |
| RAM | 8 GiB | 16 GiB |
| Disk | 50 GiB SSD | 100 GiB SSD |
| HA | 3 masters | 3 masters |

### Filer + S3 Gateway

| | Minimum | Recommended |
|--|---------|-------------|
| CPU | 8 cores | 16 cores |
| RAM | 16 GiB | 32 GiB |
| Disk | 100 GiB SSD (logs/local) | 200 GiB SSD |
| Backend | Cassandra reachable with low latency | Co-located DC / same metro |

### Cassandra (filer `seaweedfs` keyspace)

| | Minimum | Recommended |
|--|---------|-------------|
| CPU | 8 cores / node | 16 cores / node |
| RAM | 32 GiB | 64 GiB+ (heap sized per Cassandra guide; leave page cache) |
| Data disk | NVMe/SSD sized for live data + compaction headroom (~2× peaks) | Same; avoid shared spindles with volume object store |
| Nodes | RF=3 → ≥3 nodes | ≥3; rack/DC aware |

### sideweed (write LB)

| | Minimum | Recommended |
|--|---------|-------------|
| CPU | 2 cores | 4 cores |
| RAM | 2 GiB | 4 GiB |
| Disk | 20 GiB | 40 GiB |
| Placement | Same DC as S3 GW backends | HA pair / LB ahead of sideweed if required |

## Customer decisions (2026-07-31)

1. **`filemeta` TWCS ALTER:** customer applies themselves. Already applied in several environments under read pressure; **not yet** in the main playbook — use this repo’s CQL/runbook as the playbook source.
2. **Formal SLA:** none. Working targets in this document stand.
