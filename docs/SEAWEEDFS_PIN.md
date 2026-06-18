# Pin SeaweedFS fork (сборка стенда)

Стенд **не должен** собирать SeaweedFS из upstream `seaweedfs/seaweedfs` — нужен **customer fork** с патчем disk-health.

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
| **URL репозитория** | `SEAWEEDFS_REPO_URL` (env, не коммитится) |
| **Placeholder по умолчанию** | `git@github.com:<org>/seaweedfs.git` |
| **Ветка** | `feat/volume-disk-health-isolation` |
| **Commit (short)** | `1528e7d` |
| **Commit (full)** | `1528e7d6d610330ec0bc8256090005ffbe09d64c` |

`./seaweedfs` **в .gitignore** stand repo — внешний clone, не submodule.

## Нельзя использовать upstream для этого стенда

```bash
# НЕВЕРНО для сборки стенда:
git clone https://github.com/seaweedfs/seaweedfs.git seaweedfs
```

Используйте URL customer fork через `SEAWEEDFS_REPO_URL`.

## Инициализация (fresh clone)

```bash
git clone <stand-repo-url> work2
cd work2
git submodule update --init --recursive

SEAWEEDFS_REPO_URL=git@github.com:<org>/seaweedfs.git make init-seaweedfs
make check-seaweedfs
make up
make test
```

## Проверка commit вручную

```bash
cd seaweedfs
git rev-parse --short HEAD    # must print: 1528e7d
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

См. также [seaweedfs-disk-health.md](seaweedfs-disk-health.md), [seaweedfs-customer-fork.md](seaweedfs-customer-fork.md).
