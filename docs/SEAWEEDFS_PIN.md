# Pin SeaweedFS fork (сборка стенда)

Стенд **не должен** собирать SeaweedFS из upstream `seaweedfs/seaweedfs` — нужен **customer fork** с патчем disk-health.

## Репозитории

| Роль | URL |
|------|-----|
| Stand repo | `git@github.com:troyanoff97/video-storage-stand.git` |
| SeaweedFS fork (push) | `git@github.com:troyanoff97/seaweedfs.git` |
| SeaweedFS upstream (read-only) | `https://github.com/seaweedfs/seaweedfs` |
| sideweed fork | `git@github.com:troyanoff97/sideweed.git` |
| sideweed upstream (задание) | `https://github.com/targetaidev/sideweed` |

## Зачем нужен fork

В upstream нет:

- изоляции disk health по каждому `dir`
- перевода existing volumes в readonly при unhealthy dir
- пропуска readonly volume ID в master assign
- `/status` DiskHealth + немедленного heartbeat при смене health

Без закреплённого commit `make up` соберёт неверный бинарник; disk-health и chaos-тесты по S3 path будут недействительны.

## Обязательный pin

| Параметр | Значение |
|----------|----------|
| **URL репозитория** | `SEAWEEDFS_REPO_URL` (env; по умолчанию fork выше) |
| **Ветка** | `feat/volume-disk-health-isolation` |
| **Commit (short)** | `1528e7d` |
| **Commit (full)** | `1528e7d6d610330ec0bc8256090005ffbe09d64c` |

`./seaweedfs` **в .gitignore** stand repo — внешний clone, не submodule.

## Нельзя использовать upstream для этого стенда

```bash
# НЕВЕРНО для сборки стенда:
git clone https://github.com/seaweedfs/seaweedfs.git seaweedfs
```

Используйте fork: `SEAWEEDFS_REPO_URL=git@github.com:troyanoff97/seaweedfs.git`.

## Инициализация (fresh clone)

```bash
git clone git@github.com:troyanoff97/video-storage-stand.git video-storage-stand
cd video-storage-stand
git submodule update --init --recursive

SEAWEEDFS_REPO_URL=git@github.com:troyanoff97/seaweedfs.git make init-seaweedfs
make check-seaweedfs
make up
make test
```

## Проверка commit вручную

```bash
cd seaweedfs
git rev-parse --short=7 HEAD    # must print: 1528e7d
git log -1 --oneline          # must include disk-health readonly/heartbeat fix
```

Или из корня стенда:

```bash
make check-seaweedfs
```

## Скрипты

| Скрипт | Назначение |
|--------|------------|
| `scripts/init_seaweedfs.sh` | clone (если нет) + checkout pinned commit |
| `scripts/check_seaweedfs.sh` | fail-fast при отсутствии или неверном commit |

`make test-go` и `make chaos-matrix` пока **не** вызывают `check-seaweedfs` — сначала выполните `make check-seaweedfs` (или `make up`, который проверяет до сборки).

См. также [seaweedfs-disk-health.md](seaweedfs-disk-health.md), [seaweedfs-customer-fork.md](seaweedfs-customer-fork.md), [PUSH-CHECKLIST.md](PUSH-CHECKLIST.md).
