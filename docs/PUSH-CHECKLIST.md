# Безопасный push и fresh-clone checklist

**Агент не выполняет push.** Порядок: fork'и → root.  
**Не пушить:** `targetaidev/sideweed`, `seaweedfs/seaweedfs`.

Подставьте свои URL:
- `MY_SEAWEEDFS_FORK_URL` — customer SeaweedFS fork (private)
- `MY_STAND_REPO_URL` — stand repo (root)

---

## A. Sideweed → `troyanoff97/sideweed`

`origin` уже указывает на fork. Upstream задания (`targetaidev/sideweed`) — read-only.

```bash
cd sideweed
git remote -v
# origin → https://github.com/troyanoff97/sideweed.git

git push origin master
git ls-remote origin master
git branch -r --contains 551df0b
# ожидается: origin/master содержит 551df0b (commits 4c6161d, 551df0b)
```

---

## B. SeaweedFS → customer fork

Только ветка `feat/volume-disk-health-isolation`. **Не** push raw commit SHA.

```bash
cd seaweedfs
git remote -v
# upstream → seaweedfs/seaweedfs (read-only, не push)

git remote add customer MY_SEAWEEDFS_FORK_URL
# пример: git@github.com:<org>/seaweedfs.git

git checkout feat/volume-disk-health-isolation
git push -u customer feat/volume-disk-health-isolation

git ls-remote customer feat/volume-disk-health-isolation
git fetch customer feat/volume-disk-health-isolation
git branch -r --contains 1528e7d6d610330ec0bc8256090005ffbe09d64c
# ожидается: customer/feat/volume-disk-health-isolation
```

**Неверно:** `git push customer 1528e7d6d610330ec0bc8256090005ffbe09d64c`

---

## C. Root stand repo

```bash
cd <stand-repo>
git remote add origin MY_STAND_REPO_URL
git push -u origin main
git ls-remote origin main
# ожидается: HEAD main = 89d4373 (или новее)
```

Submodule pointer в root: `sideweed` @ `551df0b`.

---

## D. Fresh clone (проверка воспроизводимости)

```bash
git clone MY_STAND_REPO_URL work2-fresh
cd work2-fresh
git submodule update --init --recursive
git -C sideweed rev-parse --short HEAD
# ожидается: 551df0b

SEAWEEDFS_REPO_URL=MY_SEAWEEDFS_FORK_URL make init-seaweedfs
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
