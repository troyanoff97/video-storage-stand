# SeaweedFS fork pin (stand build)

The stand **must not** build SeaweedFS from upstream `seaweedfs/seaweedfs` — it requires a **customer fork** with the disk-health patch.

## Why a fork

Upstream does not include:

- per-`dir` disk health isolation
- existing volumes → readonly on unhealthy dir
- master assign skip for readonly volume IDs
- `/status` DiskHealth + immediate heartbeat on health change

Without the pinned commit, `make up` builds the wrong binary and disk-health / S3-path chaos tests are invalid.

## Required pin

| Item | Value |
|------|-------|
| **Repo URL** | `SEAWEEDFS_REPO_URL` (env var, not committed) |
| **Default placeholder** | `git@github.com:<org>/seaweedfs.git` |
| **Branch** | `feat/volume-disk-health-isolation` |
| **Commit (short)** | `1528e7d` |
| **Commit (full)** | `1528e7d6d610330ec0bc8256090005ffbe09d64c` |

`./seaweedfs` is **gitignored** in the stand repo — it is an external clone, not a submodule.

## Do not use upstream for this stand

```bash
# WRONG for stand builds:
git clone https://github.com/seaweedfs/seaweedfs.git seaweedfs
```

Use the customer fork URL passed via `SEAWEEDFS_REPO_URL`.

## Initialize (fresh clone)

```bash
git clone <stand-repo-url> work2
cd work2
git submodule update --init --recursive

SEAWEEDFS_REPO_URL=git@github.com:<org>/seaweedfs.git make init-seaweedfs
make check-seaweedfs
make up
make test
```

## Verify commit manually

```bash
cd seaweedfs
git rev-parse --short HEAD    # must print: 1528e7d
git log -1 --oneline          # must include disk-health readonly/heartbeat fix
```

Or from stand root:

```bash
make check-seaweedfs
```

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/init_seaweedfs.sh` | clone (if missing) + checkout pinned commit |
| `scripts/check_seaweedfs.sh` | fail fast if missing or wrong commit |

`make test-go` and `make chaos-matrix` do not call `check-seaweedfs` yet — run `make check-seaweedfs` (or `make up`, which checks before build) first.

See also [seaweedfs-disk-health.md](seaweedfs-disk-health.md), [seaweedfs-customer-fork.md](seaweedfs-customer-fork.md).
