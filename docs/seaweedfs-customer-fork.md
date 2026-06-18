# SeaweedFS customer fork — настройка

Fork: [github.com/troyanoff97/seaweedfs](https://github.com/troyanoff97/seaweedfs)  
Upstream (read-only): [github.com/seaweedfs/seaweedfs](https://github.com/seaweedfs/seaweedfs)  
Stand repo: [github.com/troyanoff97/video-storage-stand](https://github.com/troyanoff97/video-storage-stand)

## Текущее состояние (опубликовано)

| Параметр | Значение |
|----------|----------|
| Путь clone | `./seaweedfs` (gitignored в stand repo) |
| Ветка | `feat/volume-disk-health-isolation` |
| Pin commit | `1528e7d` / `1528e7d6d610330ec0bc8256090005ffbe09d64c` |
| Remote push | `customer` → `git@github.com:troyanoff97/seaweedfs.git` |
| Upstream | fetch only; `git remote set-url --push upstream DISABLED` |

## Локальная настройка remotes

```bash
cd video-storage-stand/seaweedfs

git remote -v
git remote add customer git@github.com:troyanoff97/seaweedfs.git   # если ещё нет
git remote add upstream https://github.com/seaweedfs/seaweedfs.git # если ещё нет
git remote set-url --push upstream DISABLED

git checkout feat/volume-disk-health-isolation
git push -u customer feat/volume-disk-health-isolation

git ls-remote customer feat/volume-disk-health-isolation
git branch -r --contains 1528e7d6d610330ec0bc8256090005ffbe09d64c
```

**Не использовать:** `git push customer 1528e7d6d610330ec0bc8256090005ffbe09d64c`  
**Не пушить** в `upstream` (seaweedfs/seaweedfs).

## Fresh clone stand

```bash
git clone git@github.com:troyanoff97/video-storage-stand.git
cd video-storage-stand
git submodule update --init --recursive
SEAWEEDFS_REPO_URL=git@github.com:troyanoff97/seaweedfs.git make init-seaweedfs
make check-seaweedfs
make up
```

## Сборка на volume node (bare metal)

```bash
git clone git@github.com:troyanoff97/seaweedfs.git
cd seaweedfs
git checkout feat/volume-disk-health-isolation
# docker build / weed volume — см. PRODUCTION-DEPLOY.md
```

## Проверка после deploy

```bash
docker logs <volume-container> 2>&1 | grep 'disk location'
cd video-storage-stand && make chaos-multi-dir
```

См. также: [SEAWEEDFS_PIN.md](SEAWEEDFS_PIN.md), [seaweedfs-disk-health.md](seaweedfs-disk-health.md), [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md).
