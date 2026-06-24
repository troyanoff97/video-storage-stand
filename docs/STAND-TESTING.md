# Тестирование стенда (production-like path)

## Запуск

```bash
make up
make health
make test              # PUT sideweed→S3, GET HAProxy→S3
make test-go
make test-snapshot     # snapshot PUT + GET через bucket csb (отдельный smoke)
make test-range-query  # Cassandra list по camera + time range (отдельный smoke)
make test-sideweed     # блокировка PUT при unhealthy master/volumes/S3
./scripts/verify_production_path.sh   # доказательство по логам
```

## Production PUT / GET

```bash
# Запись фрагмента: sideweed → S3 (bucket video-fragments)
./scripts/put_fragment.sh /tmp/file.bin camera-1

# Запись снимка: тот же path, bucket csb
./scripts/put_snapshot.sh /tmp/snap.bin snapshot-1
# Вывод: camera_id (= snapshot_id), fragment_id, seaweed_fid s3://csb/...

# Чтение снимка: HAProxy → sideweed-read → S3 bucket csb
./scripts/get_snapshot.sh snapshot-1 <fragment_uuid> /tmp/snap-out.bin

# Чтение фрагмента архива: bucket video-fragments
./scripts/get_fragment.sh camera-1 <fragment_uuid>

# Список фрагментов камеры за период (Cassandra timeuuid range)
./scripts/list_fragments.sh camera-1 2026-06-24T00:00:00Z 2026-06-24T23:59:59Z 100
```

## Acceptance-тесты

| Target | Path |
|--------|------|
| `make test` | Production PUT + GET (archive, bucket video-fragments) |
| `make test-snapshot` | Snapshot PUT + GET (bucket csb); metadata в `fragments`, schema-v2 не runtime |
| `make test-range-query` | LIST fragments по camera + time range (runtime schema, timeuuid bounds) |
| `make test-sideweed` | Write gate sideweed: PUT 503 при деградации кластера |
| `make chaos-multi-dir` | Отказ /data1 через S3 PUT |
| `make chaos-matrix` | Матрица отказов через S3 PUT |

Direct volume PUT в acceptance-тестах **не** используется.

## Только debug

См. [DEBUG.md](DEBUG.md).

## Порты

| Сервис | Порт | Роль |
|--------|------|------|
| sideweed | 8880 | **write entry** |
| haproxy | 8882 | **read entry** |
| s3 | 8333 | S3 Gateway |
| filer | 8888 | filer |

Учётные данные: `stand_access_key` / `stand_secret_key`

## Replication

На стенде `replication=000`, чтобы S3-записи могли расти на 2-node dev stack.

См. [README-STAND.md](../README-STAND.md), [TZ-DEVIATIONS.md](TZ-DEVIATIONS.md).
