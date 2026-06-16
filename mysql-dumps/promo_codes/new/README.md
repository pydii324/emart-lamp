# Промо кодове — миграции „от 0" (fresh install)

Чист set за **нова среда**: създава директно финалната schema, без историческите
междинни стъпки. Пълната документация на системата:
`public_html/citte/docs/promo-codes-system.md`.

## old/ или new/?

| Среда | Кое |
|---|---|
| Нова среда (нищо промо-related няма) | **new/** 01 → 18 |
| Среда, частично мигрирана с историческия път (dev, staging `emart.al`/`almarta`) | **old/** — довърши липсващите стъпки + **new/09** (drop voucher_remainer) + **new/10** (catalog SKUs), после **old/12→17 В РЕД**: `12` baza, `13` promo_fixed_discount, `14` създай регионален `cart_promo_codes`, `15` създай регионален `order_promo_codes`, `16` `shipping_percent` тип, `17` DROP на imartap `cart_promo_codes` (безопасно — **след** 14). Регионалният DB user иска SELECT/UPDATE на `imartap.promo_codes`. In-flight cart кодове се губят при cutover (transient); order история остава в imartap (preserved, не се drop-ва — per-region backfill е отделна задача) |

Двата пътя завършват в **идентична schema**. Разлики на new/ спрямо old/:
- `01`: финалната `promo_codes` директно (`times_used` вграден; БЕЗ `voucher_remainer` — voucher burn; никога не е имало `max_uses_per_user`); `CREATE TABLE IF NOT EXISTS` вместо `DROP + CREATE`.
- `03`: `order_promo_codes` с вграден `used_by_employeeId` (в old/ идва от `11-add-used-by-employee.sql`).
- `06`: `active = IF(data_validen > NOW, 1, 0)` — решението от Step 0 (в old/06 стои като open decision).
- `09`: drop на `voucher_remainer` (voucher burn — issue #610, drago 08.06). No-op за fresh (01 вече без колоната); drop-ва я за бази мигрирани преди това.
- `10`: seed на промо SKU продуктите в `catalog` (Микроинвест negative редове).
- `11`/`12`: обединени verification скриптове (old/07 + old/10 + schema sanity).
- Няма аналог на old/11 — вграден в 03.

## Ред на изпълнение

| # | Файл | Срещу | Какво |
|---|---|---|---|
| 01 | 01-create-promo_codes.sql | imartap | Главната таблица (финална schema) |
| 02 | 02-create-cart_promo_codes.sql | imartap | **LEGACY** (pre-Q1) — superseded от 14 (регионален). Създава imartap копие, което 18 drop-ва. За чист fresh install пропусни го. |
| 03 | 03-create-order_promo_codes.sql | imartap | **LEGACY** (pre-Q1) — superseded от 15 (регионален). order_promo_codes е история → imartap копието НЕ се drop-ва (нужна data миграция). |
| 04 | 04-pre-flight-checks.sql | imartap | Диагностика на source данните ПРЕДИ 05/06 (само SELECT) |
| 05 | 05-migrate-loyality_points.sql | imartap | Данни: The Marketer single-use кодове (`INSERT IGNORE`) |
| 06 | 06-migrate-obshti_kodove.sql | imartap | Данни: ръчните multi-use кодове (`INSERT IGNORE`) |
| 07 | 07-add-item-porachki-columns.sql | **всички бази** | `discount_applied` (item/item_l/item_no) + `pordost_coupon_discount` (porachki*) — guard-нат, no-op при липсваща таблица/налична колона |
| 08 | 08-drop-per-site-promo-tables.sql | **всички бази** | DROP само на per-site `promo_codes` (guard `DATABASE() <> 'imartap'`). Пивотите cart/order вече са регионални (виж 14/15) → НЕ се трият повече |
| 09 | 09-drop-voucher_remainer.sql | imartap | Voucher burn — drop на `promo_codes.voucher_remainer` (guard по column existence; no-op за fresh) |
| 10 | 10-catalog-promo-skus.sql | **всички бази** | Seed на промо SKU продукти в `catalog` (5555555/6666666/7777777/8888888, `cena=0`) — Микроинвест negative редове; guard по table existence (no-op за imartap) |
| 11 | 11-verification.sql | imartap | Data + schema sanity (само SELECT) |
| 12 | 12-verify-per-db.sql | **всички бази** | Phase 2 колоните + липса на промо таблици per region (само SELECT) |
| 13 | 13-add-baza-columns.sql | **всички бази** | Phase 1 колони `it_cena_baza`/`it_suma_baza` (item/item_l/item_no) + backfill — guard-нат, no-op при липсваща таблица/налична колона |
| 14 | 14-create-cart_promo_codes-regional.sql | **регионални** (сега: inmarta) | `cart_promo_codes` в регионалната база, без cross-DB FK — issue #610 Q1 (пивотите се местят до количката; `promo_codes` остава каталог в imartap) |
| 15 | 15-create-order_promo_codes-regional.sql | **регионални** (сега: inmarta) | `order_promo_codes` в регионалната база, без cross-DB FK — issue #610 Q1 |
| 16 | 16-add-shipping_percent-type.sql | imartap + регионални | Нов тип `shipping_percent` (процент от доставка) в `promo_codes` + `cart_promo_codes` ENUM — issue #610 Q3; guard по COLUMN_TYPE, no-op при повторно изпълнение |
| 17 | 17-add-promo-fixed-discount-cart.sql | **регионални** | `promo_fixed_discount` на `porachki_l`/`porachki_no` (mini-cart net total) — guard-нат, no-op за бази без cart headers |
| 18 | 18-drop-imartap-cart_promo_codes.sql | imartap | DROP на legacy `cart_promo_codes` от imartap (Q1: пивотът е регионален). Guard `DATABASE()='imartap'` → no-op за региони; transient таблица → без загуба на данни. Пусни СЛЕД 14. |

Всичко е идемпотентно — повторно изпълнение е no-op. **Внимание:** `CREATE TABLE IF NOT EXISTS`
не пресъздава съществуваща таблица — за истински reset първо ръчно:
```sql
USE imartap;
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS cart_promo_codes, order_promo_codes, promo_codes;
SET FOREIGN_KEY_CHECKS = 1;
```

## Изпълнение

Срещу една база (dev docker):
```bash
docker exec -i <mysql-container> mysql -uroot -p<pass> < new/01-create-promo_codes.sql
```

Срещу всички региони — batch tool-ът (стъпки 07, 08, 10, 12, 13, 14, 15, 16, 17, 18):
```bash
cd emart-monorepo/packages/db/scripts/batch-sql-dbs
cp ../../../../../mysql-dumps/promo_codes/new/07-add-item-porachki-columns.sql query.sql
bun sql-batch-dbs.ts "all19" true
```
(Tool-ът маха `--` коментари преди split на `;`; файловете нямат stored procedures — безопасни са.)

## Тестови кодове (по желание, само dev/staging)

Виж `promo-codes-test-codes.md` (repo root) / INSERT-ите в
`public_html/citte/api/promo-validate-table.sql`. Маркирани `created_by='dev-seed'` —
**изтрий преди production**: `DELETE FROM promo_codes WHERE created_by='dev-seed';`
