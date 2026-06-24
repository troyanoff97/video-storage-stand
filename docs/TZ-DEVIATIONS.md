# Соответствие стенда production architecture (подтверждено заказчиком)

## Production architecture

```
WRITE:
  client/backend → sideweed → SeaweedFS S3 Gateway → filer/master → volume nodes

READ:
  client/backend → sideweed → S3 Gateway
  или
  client/backend → HAProxy/Varnish → S3 Gateway

Snapshots: тот же write path, bucket csb
```

**Правила:**
- Клиент **никогда** не обращается к volume nodes напрямую
- sideweed балансирует **S3 Gateway**, не volume endpoints
- HAProxy/Varnish — **только read path**
- Метаданные в production пишет **SeaweedFS/filer** (не клиент)

## Стенд (этап 1+2)

| Компонент | Реализация |
|-----------|------------|
| WRITE | `sideweed:8880` → `s3:8333` |
| READ | `haproxy:8882` → `sideweed-read` → `s3:8333` |
| Fragments bucket | `video-fragments` |
| Snapshots bucket | `csb` (`scripts/put_snapshot.sh`) |
| Debug direct volume | только `scripts/debug/*` |

## Осознанные отличия стенда от production

| Production | Стенд | Причина |
|------------|-------|---------|
| Cassandra metadata via filer | Клиент пишет индекс в Cassandra | Упрощение тестового клиента `pkg/fragment` |
| Varnish перед read | Только HAProxy | Достаточно для LB read path |
| Replication 001+ | `000` на dev stack | Иначе S3 collection не растёт при 2 nodes |
| Несколько S3 GW | Один `s3:8333` | Минимальный compose |

## Только debug (не deviation)

См. [DEBUG.md](DEBUG.md):
- `master /dir/assign` + direct volume POST
- profile `sideweed-volumes` (native volume GET)
- `fragment put --direct-volume`

## SeaweedFS disk health (этап 2)

Патч volume node: unhealthy dir → volumes readonly → heartbeat → master исключает из `writables`.

Проверка через **production S3 path**: `make chaos-multi-dir`.

Полный acceptance на физическом диске: [SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md](SEAWEEDFS-BARE-METAL-DISK-TEST-PLAN.md) (ТЗ §4.2–4.5; Docker chaos — WARN/SKIP на tmpfs).

Pin fork: [SEAWEEDFS_PIN.md](SEAWEEDFS_PIN.md).

## Sideweed

Fork (push сюда): [github.com/troyanoff97/sideweed](https://github.com/troyanoff97/sideweed).  
Upstream (read-only, не push): [github.com/targetaidev/sideweed](https://github.com/targetaidev/sideweed).

- PUT/POST/GET — generic reverse proxy
- Upstream write/read: `http://s3:8333`
- Нет per-request retry; failover site/backend; proxy error → 502
- Write gate: блокировка PUT при деградации — см. [sideweed-health.md](sideweed-health.md)
