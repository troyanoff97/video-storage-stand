# Тестирование стенда (production-like path)

## Запуск

```bash
make up
make health
make test              # PUT sideweed→S3, GET HAProxy→S3
make test-go
make test-sideweed     # блокировка PUT при unhealthy master/volumes/S3
./scripts/verify_production_path.sh   # доказательство по логам
```

## Production PUT / GET

```bash
# Запись фрагмента: sideweed → S3 (bucket video-fragments)
./scripts/put_fragment.sh /tmp/file.bin camera-1

# Запись снимка: тот же path, bucket csb
./scripts/put_snapshot.sh /tmp/snap.bin snapshot-1

# Чтение: HAProxy → sideweed-read → S3
./scripts/get_fragment.sh camera-1 <fragment_uuid>
```

## Acceptance-тесты

| Target | Path |
|--------|------|
| `make test` | Production PUT + GET |
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
