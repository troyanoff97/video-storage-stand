# Безопасный push и fresh-clone checklist

Порядок публикации: **SeaweedFS fork** (уже на remote) → **sideweed fork** → **stand repo**.  
**Не пушить:** `targetaidev/sideweed`, `seaweedfs/seaweedfs` (upstream push URL в локальном clone — `DISABLED`).

## Статус публикации (актуально)

**Push выполнен.** Fresh clone verification — **PASS**.

| Repo | Remote | HEAD | Примечание |
|------|--------|------|------------|
| **root** | `origin/main` | **`336b451`** | синхронизирован |
| **sideweed** | `origin/master` | **`2a428d2`** | `/v1/write-health`, metrics |
| **submodule pointer** | — | **`2a428d2`** | `git ls-tree HEAD sideweed` |
| **SeaweedFS fork** | pin | **`1528e7d`** | без изменений в batch |

**Fresh clone:** `video-storage-stand-fresh-metrics` @ root `336b451`, sideweed `2a428d2`, seaweedfs `1528e7d`; полный suite **PASS**, `make test-sideweed` **30/30**.

---

## Исторический batch: sideweed metrics + write-health (завершён)

Ниже — порядок и проверки, использованные при публикации batch `7eadd37` → `2a428d2` и root `77bd2cd` → `336b451`. Для повторного push новых commits — тот же порядок: **sideweed first → verify remote → root second**.

### 1. Состояние на момент batch (архив)

| Repo | HEAD | vs remote (до push) | Примечание |
|------|------|---------------------|------------|
| **root** | `336b451` | было ahead 17 | `test: single-volume-down scenario` |
| **sideweed** | `2a428d2` | было ahead 2 | `feat: GET /v1/write-health` |
| **SeaweedFS fork** | pin `1528e7d` | unchanged | push не нужен |

Ключевые commits: sideweed `7eadd37` (metrics), `2a428d2` (write-health); root `adc21e0`, `77bd2cd`, `e977e64`, `f0fd8e9`, `336b451`.

### 2. Почему важен порядок push

- Root `336b451` фиксирует submodule commit **`2a428d2`**.
- Если push root **до** push sideweed, `git submodule update --init` на fresh clone не найдёт нужный commit на `origin/master` → clone **сломается**.
- **Безопасный порядок:** sideweed first → verify remote → root second.

### 3. Pre-push checks (перед любым новым push)

Оба repo должны быть **clean**. Затем на root:

```bash
git status -sb
git -C sideweed status -sb
git submodule status
git ls-tree HEAD sideweed
# ожидается: 2a428d2... (или актуальный pointer)

make health
make test
make test-snapshot
make test-range-query
make verify-path
make test-sideweed
go test ./...
```

Ожидание: все команды **PASS** (`make test-sideweed`: PASS=30 FAIL=0).

### 4. Push commands (шаблон)

**Sideweed first:**

```bash
cd sideweed
git push origin master
git ls-remote origin master
# ожидается: актуальный sideweed HEAD на refs/heads/master

git branch -r --contains <sideweed-sha>
# ожидается: origin/master
```

**Root second:**

```bash
cd ..
git push origin main
git ls-remote origin main
# ожидается: актуальный root HEAD на refs/heads/main
```

### 5. Fresh clone verification (после push)

Использовать **отдельную директорию** (на том же хосте — остановить другой stand или другой порт; см. §6).

```bash
git clone git@github.com:troyanoff97/video-storage-stand.git video-storage-stand-fresh-metrics
cd video-storage-stand-fresh-metrics
git submodule update --init --recursive
git -C sideweed rev-parse --short HEAD
# ожидается: 2a428d2 (или актуальный pointer)

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

### 6. Известные риски

| Риск | Mitigation |
|------|------------|
| Root pushed before sideweed | **Всегда** push sideweed first; verify `git branch -r --contains <sha>` |
| Fresh clone fails mid-batch | Не push root, пока sideweed commit не на remote |
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

**На remote:** `origin/master` @ **`2a428d2`** (write gate + metrics + `/v1/write-health`).

```bash
cd sideweed
git remote -v
# origin → troyanoff97/sideweed

git push origin master
git ls-remote origin master
git branch -r --contains 2a428d2
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

**На remote:** `origin/main` @ **`336b451`**.

```bash
git remote add origin git@github.com:troyanoff97/video-storage-stand.git
git push -u origin main
git ls-remote origin main
```

Submodule pointer: `sideweed` @ **`2a428d2`**.

---

## D. Fresh clone (проверка воспроизводимости)

**Подтверждено:** clone `video-storage-stand-fresh-metrics` — root `336b451`, sideweed `2a428d2`, seaweedfs `1528e7d`; suite PASS, `test-sideweed` 30/30.

Шаблон для повторной проверки:

```bash
git clone git@github.com:troyanoff97/video-storage-stand.git work2-fresh
cd work2-fresh
git submodule update --init --recursive
git -C sideweed rev-parse --short HEAD
# ожидается: 2a428d2

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
