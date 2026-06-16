# SeaweedFS customer private fork — setup (manual push)

Instructions for preparing the patched SeaweedFS branch for the customer's private GitHub fork (Aziz TZ §4.1). **The agent does not push**; you push manually when ready.

## Current local state

| Item | Value |
|------|-------|
| Clone path | `./seaweedfs` (gitignored in stand repo) |
| Branch | `feat/volume-disk-health-isolation` |
| Base | upstream tag 3.80 |
| Stand image | `docker/seaweedfs.Dockerfile` → `work2-seaweedfs:local` |

Commits on the branch include disk health isolation and follow-up fixes (single `-dir` unhealthy startup, `addVolume` disk error reporting).

## 1. Create private fork on GitHub (customer org)

1. Customer creates empty private repo, e.g. `github.com/<customer>/seaweedfs`.
2. Do **not** use a public fork if the contract requires private code.

## 2. Add remote and push (you, manually)

```bash
cd /home/cerf/Desktop/work2/seaweedfs

git remote -v
# upstream should point to seaweedfs/seaweedfs

git remote add customer git@github.com:<customer>/seaweedfs.git
# or HTTPS: https://github.com/<customer>/seaweedfs.git

git checkout feat/volume-disk-health-isolation
git log --oneline -5   # verify commits

git push -u customer feat/volume-disk-health-isolation
# optional: git push customer feat/volume-disk-health-isolation:main
```

## 3. Build and deploy on a volume node

```bash
# From stand repo (uses local ./seaweedfs context)
cd /home/cerf/Desktop/work2
make up   # builds work2-seaweedfs:local

# Or on bare metal from customer fork:
git clone git@github.com:<customer>/seaweedfs.git
cd seaweedfs
git checkout feat/volume-disk-health-isolation
cd docker
docker build -t seaweedfs-disk-health:prod -f Dockerfile.local ../..
```

Run volume server (production: typically one `-dir` per node on RAID mount):

```bash
weed volume -mserver=master:9333 -dir=/mnt/raid/volume -max=8 \
  -ip=<volume-host> -dataCenter=dc1 -rack=rack1
```

Multi-dir on one node (lab / stand):

```bash
weed volume -dir=/data1,/data2 -max=3,3 -mserver=master:9333
```

## 4. Verify after deploy

```bash
# Logs on disk fault
docker logs <volume-container> 2>&1 | grep 'disk location'

# Expected patterns:
#   marked unhealthy (...); new writes disabled on this directory
#   recovered and is healthy again; writes re-enabled

# Stand regression (optional)
cd /home/cerf/Desktop/work2
make chaos-multi-dir
```

## 5. What is **not** in this fork

- Cassandra csb/vab (Aziz §5) — separate work
- sideweed PUT blocking (Aziz §6.2–6.4) — sideweed fork: `troyanoff97/sideweed`
- Prometheus `/status` disk health gauge (optional §4.4) — not implemented yet

## 6. Stand repo relationship

The stand repo references `./seaweedfs` only at **build time**. CI/production should clone the **customer fork**, not rely on the developer's local path.

See also: [seaweedfs-disk-health.md](seaweedfs-disk-health.md), [STAND-TESTING.md](STAND-TESTING.md).
