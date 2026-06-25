# Runbook: миграция camera snapshots vab → csb

**Internal runbook.** Не production change. Применение — только в change window заказчика.

**Связанные документы:** [PRODUCTION-CONFIG-AUDIT.md](PRODUCTION-CONFIG-AUDIT.md), [CASSANDRA-TASK-STATUS.md](CASSANDRA-TASK-STATUS.md), [TZ-ACCEPTANCE-MATRIX.md](TZ-ACCEPTANCE-MATRIX.md) §5.1

---

## 1. Current state (production audit)

| Поток | Bucket | Примечание |
|-------|--------|------------|
| Video archive (streamserver) | **vab** | Основной архив |
| Camera snapshots (write) | **vab** | Сейчас пишутся в vab |
| Event snapshots | **esb** | Отдельный bucket |
| Camera snapshots (read path) | **csb** | Varnish/HAProxy **уже** настроены на `/s3/csb` (read-ready) |
| sideweed | bucket-agnostic | Прокси на S3 GW, bucket в path |

**Вывод:** read path для csb готов; **write migration не применена**.

---

## 2. Target state

| Bucket | Назначение |
|--------|------------|
| **vab** | Только video archive |
| **csb** | Camera snapshots (write + read) |
| **esb** | Event snapshots (без изменений) |

---

## 3. Config candidates (не применять без sign-off)

| Компонент | Текущее (audit) | Целевое |
|-----------|-----------------|---------|
| streamserver `[[streamers.snapshot]].bucket_name` | `vab` | `csb` |
| teye `[snapshots].camera_base_url` | `/s3/vab` | `/s3/csb` |
| Varnish / HAProxy | csb backend уже есть | **Вероятно без изменений** |
| sideweed | — | **Без изменений** (bucket-agnostic) |
| SeaweedFS filer buckets | vab, csb, esb exist | Создать/проверить csb write ACL |

**Secrets и полные конфиги** — только у заказчика; в docs не копировать.

---

## 4. Migration strategy

### 4.1 Принципы

1. **Не удалять** старые snapshots в vab.
2. **Новые** snapshots → csb после переключения streamserver.
3. **Read compatibility period:**
   - prefer **csb** для новых объектов;
   - fallback на **vab** для старых — **только если** приложение поддерживает (уточнить у заказчика).
4. **Rollback:** вернуть streamserver bucket → vab, teye `camera_base_url` → `/s3/vab`.

### 4.2 Порядок (предложение)

1. Подтвердить bucket `csb` на filer/S3 (quota, ACL).
2. Staging: PUT/GET snapshot в csb (`make test-snapshot` на stand).
3. Change window: streamserver `bucket_name` → csb.
4. teye `camera_base_url` → `/s3/csb` (согласовать порядок с streamserver).
5. Smoke: новый snapshot, GET через Varnish, старый из vab (если fallback).
6. Мониторинг: S3 errors, sideweed `put_blocked`, Cassandra/filemeta growth.

---

## 5. Verification checklist

- [ ] PUT нового camera snapshot → объект в **csb**
- [ ] GET нового snapshot через production read path (Varnish/HAProxy)
- [ ] Старый snapshot в **vab** всё ещё читается
- [ ] Varnish TTL/caching корректен для csb
- [ ] Нет роста 503 на sideweed write path
- [ ] Cassandra / `filemeta` (если используется) — ожидаемый рост только по новым ключам

---

## 6. Risks

| Risk | Mitigation |
|------|------------|
| Старые deep links на `/s3/vab/...` | Fallback read или redirect policy |
| Varnish cache stale | Purge / TTL review |
| Mixed buckets в UI | Документировать период dual-read |
| Нет app fallback | **Блокер** — согласовать до cutover |
| Неверный streamserver bucket | Rollback + smoke |

---

## 7. Required from customer

- [ ] Финальные streamserver / teye configs (redacted в ticket)
- [ ] Change window и rollback owner
- [ ] Retention старых snapshots в vab
- [ ] Нужен ли **fallback read** vab для camera snapshots
- [ ] Подтверждение csb quota и backup policy

---

## 8. Stand reference

```bash
make test-snapshot   # PUT/GET csb на stand
```

Stand bucket `csb` — smoke only; не отражает prod data volume.

---

*Migration **not applied**. Этот документ — runbook для будущего cutover.*
