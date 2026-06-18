# Развёртывание в production

Архитектура, подтверждённая заказчиком:

```
WRITE:  client → sideweed → S3 Gateway → filer/master → volume nodes
READ:   client → sideweed  OR  HAProxy/Varnish → S3 Gateway
```

Клиенты в production **никогда** не вызывают volume nodes напрямую.

## Компоненты стека

| Компонент | Роль |
|-----------|------|
| **sideweed** | LB для endpoint'ов S3 Gateway (write + опционально read) |
| **SeaweedFS S3 Gateway** | S3 API; работает с filer |
| **SeaweedFS filer** | Метаданные; назначает chunks через master |
| **SeaweedFS master** | Topology, volume assign |
| **SeaweedFS volume** | Blob storage (`-dir` на диск) |
| **HAProxy / Varnish** | Только read path (не write) |
| **Cassandra** | Метаданные приложения (в production: через интеграцию filer) |

## Buckets

| Bucket | Содержимое |
|--------|------------|
| `video-fragments` (или app-specific) | Видеофрагменты |
| `csb` | Снимки |

На стенде: `scripts/put_fragment.sh` (фрагменты), `scripts/put_snapshot.sh` (csb).

## Volume node (патч disk-health)

Ветка: `feat/volume-disk-health-isolation` в customer SeaweedFS fork.  
**Pinned commit:** `1528e7d` — см. [SEAWEEDFS_PIN.md](SEAWEEDFS_PIN.md).

Клонирование стенда:

```bash
SEAWEEDFS_REPO_URL=git@github.com:<org>/seaweedfs.git make init-seaweedfs
make check-seaweedfs
```

При unhealthy dir:
- Existing volumes → readonly (heartbeat в master)
- Master прекращает assign на этих volume ID
- Новый рост только на healthy dirs (`FindFreeLocation`)

Мониторинг: `/status` → `DiskHealth`, `ReadOnlyVolumeIds`; метрика `seaweed_volumeServer_disk_healthy{dir}`.

Пример команды volume в production:

```bash
weed volume -dir=/mnt/disk1,/mnt/disk2 -max=32,32 -mserver=... -metricsPort=9324
```

## Конфигурация sideweed

Fork для push: [github.com/troyanoff97/sideweed](https://github.com/troyanoff97/sideweed).  
Upstream (read-only, не push): [github.com/targetaidev/sideweed](https://github.com/targetaidev/sideweed).

```bash
sideweed -l --json --health-path=/healthz --health-duration=3s \
  --address=:8880 http://s3-gw-1:8333 http://s3-gw-2:8333
```

- Health path должен возвращать HTTP 200 (`/healthz` на SeaweedFS S3)
- Поддерживаются только `http://` upstream'ы
- Нет retry на уровне запроса; failed proxy помечает backend DOWN

Read path (пример):

```text
HAProxy → sideweed-read → S3 Gateway pool
```

## Проверка перед production

На patched image / стенде:

```bash
git submodule update --init --recursive
SEAWEEDFS_REPO_URL=git@github.com:<org>/seaweedfs.git make init-seaweedfs
make check-seaweedfs
make up
make test                    # PUT sideweed→S3, GET HAProxy→S3
./scripts/verify_production_path.sh
make chaos-multi-dir         # per-dir disk health via S3 path
```

Тесты direct volume: только [DEBUG.md](DEBUG.md).

## Чеклист: стенд vs production

- [ ] sideweed upstream = S3 Gateway (не volume)
- [ ] Write path не открывает volume ports клиентам
- [ ] Read path через HAProxy/Varnish → S3
- [ ] Снимки в bucket `csb`
- [ ] Патч disk-health на volume nodes
- [ ] Алерты на `disk_healthy == 0`

См. также [seaweedfs-disk-health.md](seaweedfs-disk-health.md), [seaweedfs-customer-fork.md](seaweedfs-customer-fork.md), [SEAWEEDFS_PIN.md](SEAWEEDFS_PIN.md).
