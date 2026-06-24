# Безопасный push и fresh-clone checklist

Порядок публикации: **SeaweedFS fork** (уже на remote) → **sideweed fork** → **stand repo**.  
**Не пушить:** `targetaidev/sideweed`, `seaweedfs/seaweedfs` (upstream push URL в локальном clone — `DISABLED`).

## Current local push readiness — sideweed metrics batch

**Статус:** push **не выполнялся** (документ только для будущего прогона).  
**Актуально на:** root `77bd2cd`, sideweed `7eadd37`.

### 1. Current local state

| Repo | HEAD | vs remote | Working tree | Примечание |
|------|------|-----------|--------------|------------|
| **root** (`video-storage-stand`) | `77bd2cd` | **ahead 12** | clean | `docs: add sideweed alerting examples` |
| **sideweed** (submodule) | `7eadd37` | **ahead 1** | clean | `feat: expose Prometheus metrics` |
| **root submodule pointer** | `7eadd37` | — | — | `git ls-tree HEAD sideweed` |
| **sideweed `origin/master`** | `551df0b` | on remote | — | metrics commit **ещё не** на remote |
| **SeaweedFS fork** | pin `1528e7d` | unchanged | — | уже опубликован, push не нужен для этого batch |

Ключевые локальные commits в batch: sideweed `7eadd37`, root `adc21e0` (metrics pointer), `77bd2cd` (observability sample configs).

### 2. Why push order matters

- Root `77bd2cd` фиксирует submodule commit **`7eadd37`**.
- Если push root **до** push sideweed, `git submodule update --init` на fresh clone не найдёт `7eadd37` на `origin/master` → clone **сломается**.
- **Безопасный порядок:** sideweed first → verify remote → root second.

### 3. Pre-push checks (локально, перед push)

Оба repo должны быть **clean**. Затем на root:

```bash
git status -sb
git -C sideweed status -sb
git submodule status
git ls-tree HEAD sideweed
# ожидается: 7eadd37a7c32623227ece32db51e77d64f8ae9b2

make health
make test
make test-snapshot
make test-range-query
make verify-path
make test-sideweed
go test ./...
```

Ожидание: все команды **PASS** (test-sideweed: PASS=13 FAIL=0).

### 4. Push commands — **DO NOT RUN NOW**

Выполнять только после явного решения о push и успешных pre-push checks.

**Sideweed first:**

```bash
cd sideweed
git push origin master
git ls-remote origin master
# ожидается: 7eadd37... на refs/heads/master

git branch -r --contains 7eadd37
# ожидается: origin/master
```

**Root second:**

```bash
cd ..
git push origin main
git ls-remote origin main
# ожидается: 77bd2cd... на refs/heads/main
```

### 5. Fresh clone verification (после push)

Использовать **отдельную директорию** (на том же хосте — остановить другой stand или другой порт; см. §6).

```bash
git clone git@github.com:troyanoff97/video-storage-stand.git video-storage-stand-fresh-metrics
cd video-storage-stand-fresh-metrics
git submodule update --init --recursive
git -C sideweed rev-parse --short HEAD
# ожидается: 7eadd37

SEAWEEDFS_REPO_URL=git@github.com:troyanoff97/seaweedfs.git make init-seaweedfs
make check-seaweedfs
# ожидается: OK: seaweedfs at 1528e7d

make up
make health
make test
make test-snapshot
make test-range-query
make verify-path
make test-sideweed
curl -fsS http://localhost:8880/metrics | grep sideweed_write_health_status
curl -fsS http://localhost:8880/v1/write-health | grep '"status":"healthy"'
```

### 6. Known risks

| Risk | Mitigation |
|------|------------|
| Root pushed before sideweed | **Всегда** push sideweed first; verify `git branch -r --contains 7eadd37` |
| Fresh clone fails mid-batch | Не push root, пока sideweed `7eadd37` не на remote |
| Port conflict (two stands) | Один stand на хост; для fresh clone — другая директория, `docker compose down` в старом stand (без `-v`) |
| SeaweedFS upstream accidental push | `git remote set-url --push upstream DISABLED` в локальном `seaweedfs/` |
| Alertmanager delivery | **Не реализовано** — только metrics + sample rules в `observability/` |
| Production Cassandra DDL | `schema-v2.cql` experimental; runtime `schema.cql` без изменений |
| Bare-metal disk tests | План есть; прогон на metal ещё не зафиксирован |

---

## Репозитории (фактические URL)

| Роль | URL |
|------|-----|
| Stand repo | `git@github.com:troyanoff97/video-storage-stand.git` |
| SeaweedFS fork | `git@github.com:troyanoff97/seaweedfs.git` |
| SeaweedFS upstream (read-only) | `https://github.com/seaweedfs/seaweedfs` |
| sideweed fork | `git@github.com:troyanoff97/sideweed.git` |
| sideweed upstream (задание) | `https://github.com/targetaidev/sideweed` |

Go module stand repo: `github.com/troyanoff97/video-storage-stand`.

---

## A. Sideweed → `troyanoff97/sideweed`

**Исторически:** `551df0b` уже был на remote (write gate).  
**Текущий batch:** локально `7eadd37` (metrics) — см. раздел **Current local push readiness** выше.

```bash
cd sideweed
git remote -v
# origin → troyanoff97/sideweed

git push origin master
git ls-remote origin master
git branch -r --contains 7eadd37
```

---

## B. SeaweedFS → customer fork ✓ (уже на remote)

Только ветка `feat/volume-disk-health-isolation`. **Не** push raw commit SHA.

```bash
cd seaweedfs
git remote -v
# customer → troyanoff97/seaweedfs
# upstream fetch only; push URL = DISABLED

git push -u customer feat/volume-disk-health-isolation

git ls-remote customer feat/volume-disk-health-isolation
git fetch customer feat/volume-disk-health-isolation
git branch -r --contains 1528e7d6d610330ec0bc8256090005ffbe09d64c
```

**Неверно:** `git push customer 1528e7d6d610330ec0bc8256090005ffbe09d64c`

Защита upstream от случайного push (локально, один раз):

```bash
git remote set-url --push upstream DISABLED
```

---

## C. Root stand repo

**Исторически:** `main` уже на remote @ более раннем pointer.  
**Текущий batch:** push после sideweed `7eadd37`; ожидаемый submodule pointer **`7eadd37`**.

```bash
git remote add origin git@github.com:troyanoff97/video-storage-stand.git
git push -u origin main
git ls-remote origin main
```

Submodule pointer после push: `sideweed` @ **`7eadd37`**.

---

## D. Fresh clone (проверка воспроизводимости)

**До push metrics batch:** remote submodule остаётся на `551df0b` — fresh clone **не** включает `7eadd37`.  
**После push:** полный прогон — в разделе **Current local push readiness → §5**.

Краткий шаблон (обновить ожидаемый SHA после push):

```bash
git clone git@github.com:troyanoff97/video-storage-stand.git work2-fresh
cd work2-fresh
git submodule update --init --recursive
git -C sideweed rev-parse --short HEAD
# после metrics push ожидается: 7eadd37

SEAWEEDFS_REPO_URL=git@github.com:troyanoff97/seaweedfs.git make init-seaweedfs
make check-seaweedfs
# ожидается: OK: seaweedfs at 1528e7d

make up
make test
make test-sideweed
make verify-path
curl -fsS http://localhost:8880/metrics | grep sideweed_write_health_status
curl -fsS http://localhost:8880/v1/write-health | grep '"status":"healthy"'
```

---

## Ссылки

- SeaweedFS pin: [SEAWEEDFS_PIN.md](SEAWEEDFS_PIN.md)
- SeaweedFS fork setup: [seaweedfs-customer-fork.md](seaweedfs-customer-fork.md)
- Sideweed write gate: [sideweed-health.md](sideweed-health.md)
- Sideweed alerting / observability samples: [SIDEWEED-ALERTING.md](SIDEWEED-ALERTING.md), `observability/`
