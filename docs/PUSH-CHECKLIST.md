# Безопасный push и fresh-clone checklist

Порядок первичной публикации: SeaweedFS fork → sideweed fork → stand repo.  
**Не пушить:** `targetaidev/sideweed`, `seaweedfs/seaweedfs` (upstream push URL в локальном clone — `DISABLED`).

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

## A. Sideweed → `troyanoff97/sideweed` ✓ (уже на remote)

```bash
cd sideweed
git remote -v
# origin → troyanoff97/sideweed

git push origin master
git ls-remote origin master
git branch -r --contains 551df0b
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

## C. Root stand repo ✓ (уже на remote)

```bash
git remote add origin git@github.com:troyanoff97/video-storage-stand.git
git push -u origin main
git ls-remote origin main
```

Submodule pointer: `sideweed` @ `551df0b`.

---

## D. Fresh clone (проверка воспроизводимости)

```bash
git clone git@github.com:troyanoff97/video-storage-stand.git work2-fresh
cd work2-fresh
git submodule update --init --recursive
git -C sideweed rev-parse --short HEAD
# ожидается: 551df0b

SEAWEEDFS_REPO_URL=git@github.com:troyanoff97/seaweedfs.git make init-seaweedfs
make check-seaweedfs
# ожидается: OK: seaweedfs at 1528e7d

make up
make test
make test-sideweed
make verify-path
```

---

## Ссылки

- SeaweedFS pin: [SEAWEEDFS_PIN.md](SEAWEEDFS_PIN.md)
- SeaweedFS fork setup: [seaweedfs-customer-fork.md](seaweedfs-customer-fork.md)
- Sideweed write gate: [sideweed-health.md](sideweed-health.md)
