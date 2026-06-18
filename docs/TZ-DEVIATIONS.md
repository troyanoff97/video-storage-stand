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
- Metadata в production пишет **SeaweedFS/filer** (не клиент)

## Стенд (этап 1+2)

| Компонент | Реализация |
|-----------|------------|
| WRITE | `sideweed:8880` → `s3:8333` |
| READ | `haproxy:8882` → `sideweed-read` → `s3:8333` |
| Fragments bucket | `video-fragments` |
| Snapshots bucket | `csb` (`scripts/put_snapshot.sh`) |
| Debug direct volume | `scripts/debug/*` only |

## Осознанные отличия стенда от production

| Production | Стенд | Причина |
|------------|-------|---------|
| Cassandra metadata via filer | Клиент пишет индекс в Cassandra | Упрощение тестового клиента `pkg/fragment` |
| Varnish перед read | Только HAProxy | Достаточно для LB read path |
| Replication 001+ | `000` на dev stack | Иначе S3 collection не растёт при 2 nodes |
| Несколько S3 GW | Один `s3:8333` | Минимальный compose |

## Debug-only (не deviation)

См. [DEBUG.md](DEBUG.md):
- `master /dir/assign` + direct volume POST
- `sideweed-volumes` profile (native volume GET)
- `fragment put --direct-volume`

## SeaweedFS disk health (этап 2)

Патч volume node: unhealthy dir → volumes readonly → heartbeat → master исключает из `writables`.

Проверка через **production S3 path**: `make chaos-multi-dir`.

## Sideweed

- PUT/POST/GET — generic reverse proxy
- Upstream write/read: `http://s3:8333`
- Нет per-request retry; failover site/backend; proxy error → 502
