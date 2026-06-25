# SeaweedFS disk simulation — E2E overlay (design)

**Status:** documented next step. **Not implemented** in stand runtime (risk / scope).

**Goal:** связать host loopback mounts (`scripts/disk-sim/`) с **реальным** `weed volume -dir` через docker bind mount и проверить, что full/ro/unavailable mount влияет на volume server behavior.

**Связанные:** [SEAWEEDFS-ENHANCED-DISK-SIMULATION.md](SEAWEEDFS-ENHANCED-DISK-SIMULATION.md), [SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md](SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md)

---

## 1. Current vs target

| Layer | Today | E2E overlay |
|-------|-------|-------------|
| Host disk fault | `scripts/disk-sim/` on loopback under `/tmp/seaweedfs-disk-sim` | Same paths **bind-mounted** into volume container |
| SeaweedFS | Docker named volumes `/data` | `-dir=/mnt/stor1` → host loopback |
| Proof | Host mount state + manual logs | weed volume logs + master topology + assign |

Enhanced sim **verified PASS** (2026-06-25) без E2E — достаточно для local TZ partial.

---

## 2. Proposed architecture

```
Host: /tmp/seaweedfs-disk-sim/mnt/stor1 (loop ext4)
        ↓ bind mount
Container weed-volume: -dir=/mnt/stor1
        ↓
Master assign / heartbeat reflects dir health
```

Отдельный compose project (не основной stand):

- `docker-compose.disk-sim.yml`
- `COMPOSE_PROJECT_NAME=seaweedfs-disk-sim-e2e`
- Только `/tmp/seaweedfs-disk-sim` — **no production paths**

---

## 3. Proposed scripts

| Script | Role |
|--------|------|
| `scripts/disk-sim/e2e_up.sh` | `CONFIRM_DISK_SIM=1`, setup loopback, compose up |
| `scripts/disk-sim/e2e_test.sh` | disk full → volume log; recovery |
| `scripts/disk-sim/e2e_down.sh` | compose down **without** `-v` |

---

## 4. Safety constraints

- `CONFIRM_DISK_SIM=1` required
- **No** `docker compose down -v`
- **No** delete docker volumes on main stand
- Separate project name
- Sudo only under `/tmp/seaweedfs-disk-sim`

---

## 5. Why not implemented now

1. **Risk:** bind mount + SeaweedFS volume state может конфликтовать с основным `docker-compose.yml` volumes.
2. **Scope:** enhanced host sim уже **local verified**; E2E — incremental proof.
3. **Maintenance:** отдельный compose stack требует CI/time не в текущем milestone.

---

## 6. Implementation checklist (future)

- [ ] `docker-compose.disk-sim.yml` — minimal master + 1 volume, bind `/tmp/.../mnt/stor1`
- [ ] Reuse `common.sh` from disk-sim
- [ ] Document expected log lines from fork disk-health patch
- [ ] Makefile targets: `disk-sim-e2e-up`, `disk-sim-e2e-test`, `disk-sim-e2e-down`
- [ ] Run once manually; record in §12 style verification block

---

## 7. Alternative

Bare-metal test plan on customer isolated node — **authoritative** sign-off when available.

---

*Next step when team accepts separate compose project risk.*
