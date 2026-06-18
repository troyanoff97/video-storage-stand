# Ожидания chaos-тестов (production S3 path)

Обновлять после `make chaos-matrix` или `make chaos-multi-dir`.

Все acceptance PUT/GET используют:
- **PUT:** `scripts/put_fragment.sh` → sideweed:8880 → S3 Gateway:8333
- **GET:** `scripts/get_fragment.sh` → HAProxy:8882 → sideweed-read → S3:8333

Write sideweed и read sideweed-read — **разные entrypoint'ы**. Direct volume PUT — только debug ([DEBUG.md](DEBUG.md)).

## Метки результата (`make chaos-matrix`)

| Метка | Значение |
|-------|----------|
| **PASS** | Поведение соответствует ожиданиям production |
| **WARN** | Симуляция отказа не применилась (ограничение tmpfs/remount на стенде) |
| **SKIP** | Проверка пропущена — отказ не воспроизведён |
| **FAIL** | Регрессия production path — неожиданный успех или отказ |

Matrix завершается с ненулевым кодом только при **FAIL**.

## Sideweed (S3 upstream)

- Health: `GET /healthz` на S3 Gateway
- PUT проксируется на `http://s3:8333` — trace log `"method":"PUT"`
- S3 down → sideweed 502, backend помечен DOWN
- Нет per-request retry

## Write gate sideweed (`make test-sideweed`)

Write sideweed (`:8880`) проверяет S3, filer, master и `/dir/assign` перед разрешением PUT.

| Отказ | PUT (write sideweed) | GET (read path) |
|-------|----------------------|-----------------|
| master down | **503** fast (`PUT_BLOCKED`) | OK (существующий объект) |
| all volumes down | **503** | FAIL при volumes down |
| S3 down | **503** fast (`s3_backend_down`) | FAIL при сломанном volumes/S3 path |
| write sideweed down | connection refused | OK через HAProxy/sideweed-read |
| recovered | PUT OK (`RECOVERED` log) | OK |

Read sideweed (`sideweed-read`) **без** write gate.

Подробнее: [sideweed-health.md](sideweed-health.md)

## Сценарии matrix (`make chaos-matrix`)

Стенд: `replication=000`, два volume node.

| # | Сценарий | PUT (S3 через write sideweed) | GET (HAProxy → read path) |
|---|----------|-------------------------------|---------------------------|
| 0 | baseline | PASS | PASS |
| 1 | volume1 down, volume2 up | **PASS** (failover на volume2) | PASS (существующий объект) |
| 2 | mount unavailable v1 (v2 stopped) | FAIL если отказ применён; иначе SKIP | — |
| 3 | disk full v1 (v2 stopped) | FAIL если отказ применён; иначе SKIP | — |
| 4 | disk ro v1 (v2 stopped) | FAIL если отказ применён; иначе SKIP | PASS baseline после восстановления v2 |
| 5 | master down | **FAIL** (503 write gate или ошибка S3) | optional (существующий объект может PASS) |
| 6 | all volumes down | FAIL | FAIL |
| 7 | write sideweed down | FAIL | **PASS** (read через sideweed-read) |

### Почему такие ожидания

- **volume1 down:** При `replication=000` и здоровом volume2 S3 может выделить место на volume2 — успешный PUT корректное HA-поведение, не отказ.
- **master down:** Новые записи требуют master assign → PUT должен падать. GET уже сохранённого объекта может работать через filer/S3/volumes без master.
- **sideweed down:** Write entrypoint недоступен → PUT падает. Read идёт через HAProxy → sideweed-read → S3 → не затронут.
- **disk faults:** Если tmpfs remount/fill не применился, matrix пишет **WARN** + **SKIP** вместо ложного PASS/FAIL.

## Multi-dir (`make chaos-multi-dir`)

- baseline PUT-S3 OK
- отказ /data1 → PUT-S3 всё ещё OK (запись через /data2)
- логи: `marked unhealthy.*data1`, `In dir /data2 adds volume`
- sideweed trace: PUT → `s3:8333`

## Debug assign checks

`master /dir/assign` тестируется только через `scripts/debug/master_assign.sh` в recovery/matrix diagnostics.

См. [STAND-TESTING.md](STAND-TESTING.md).
