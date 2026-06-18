# SeaweedFS customer private fork — настройка (ручной push)

Инструкция по подготовке patched ветки SeaweedFS для private GitHub fork заказчика (Aziz TZ §4.1). **Агент не выполняет push** — вы пушите вручную, когда готовы.

**Не пушить** в upstream `seaweedfs/seaweedfs`.

## Текущее локальное состояние

| Параметр | Значение |
|----------|----------|
| Путь clone | `./seaweedfs` (gitignored в stand repo) |
| Ветка | `feat/volume-disk-health-isolation` |
| Pin commit | `1528e7d` / `1528e7d6d610330ec0bc8256090005ffbe09d64c` |
| База | upstream tag 3.80 |
| Образ стенда | `docker/seaweedfs.Dockerfile` → `work2-seaweedfs:local` |

На ветке — disk health isolation и последующие исправления (unhealthy startup при одном `-dir`, reporting disk error в `addVolume`).

## 1. Создать private fork на GitHub (org заказчика)

1. Заказчик создаёт пустой private repo, например `github.com/<customer>/seaweedfs`.
2. Не использовать public fork, если контракт требует private code.

## 2. Добавить remote и push (вручную)

```bash
cd <stand-repo>/seaweedfs

git remote -v
# upstream должен указывать на seaweedfs/seaweedfs (read-only)

git remote add customer git@github.com:<customer>/seaweedfs.git
# или HTTPS: https://github.com/<customer>/seaweedfs.git

git checkout feat/volume-disk-health-isolation
git log --oneline -5   # verify commits

git push -u customer feat/volume-disk-health-isolation
# опционально: git push customer feat/volume-disk-health-isolation:main
```

## 3. Сборка и deploy на volume node

```bash
# Из stand repo (использует локальный ./seaweedfs context)
cd <stand-repo>
make up   # builds work2-seaweedfs:local

# Или на bare metal из customer fork:
git clone git@github.com:<customer>/seaweedfs.git
cd seaweedfs
git checkout feat/volume-disk-health-isolation
cd docker
docker build -t seaweedfs-disk-health:prod -f Dockerfile.local ../..
```

Запуск volume server (production: обычно один `-dir` на node на RAID mount):

```bash
weed volume -mserver=master:9333 -dir=/mnt/raid/volume -max=8 \
  -ip=<volume-host> -dataCenter=dc1 -rack=rack1
```

Multi-dir на одном node (lab / стенд):

```bash
weed volume -dir=/data1,/data2 -max=3,3 -mserver=master:9333
```

## 4. Проверка после deploy

```bash
# Логи при disk fault
docker logs <volume-container> 2>&1 | grep 'disk location'

# Ожидаемые паттерны:
#   marked unhealthy (...); new writes disabled on this directory
#   recovered and is healthy again; writes re-enabled

# Регрессия на стенде (опционально)
cd <stand-repo>
make chaos-multi-dir
```

## 5. Чего **нет** в этом fork

- Cassandra csb/vab (Aziz §5) — отдельная работа
- Блокировка PUT sideweed (Aziz §6.2–6.4) — fork sideweed: `troyanoff97/sideweed`
- Prometheus `/status` disk health gauge (опционально §4.4) — пока не реализовано

## 6. Связь со stand repo

Stand repo ссылается на `./seaweedfs` только на **этапе сборки**. CI/production должны клонировать **customer fork**, а не полагаться на локальный путь разработчика.

См. также: [SEAWEEDFS_PIN.md](SEAWEEDFS_PIN.md), [seaweedfs-disk-health.md](seaweedfs-disk-health.md), [STAND-TESTING.md](STAND-TESTING.md).
