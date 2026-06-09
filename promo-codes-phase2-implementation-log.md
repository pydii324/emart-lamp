# Promo Phase 2 — отстъпка „вътре в артикула" + Микроинвест

Имплементация на договореното: промо отстъпката вече се **записва** в `it_cena`/`it_suma` per артикул (Phase 2), с audit колона `discount_applied`. Ваучер/доставка купони се водят отделно. Промо таблиците стават единен източник в `imartap`.

## Трите фази на цената

| Фаза | Носител | Източник |
|---|---|---|
| 0 | `it_osnovna_cena` | каталожна цена × курс |
| 1 | `it_cena` / `it_suma` | меню/количествени/продуктови отстъпки (при add-to-cart) |
| 2 | `it_cena` / `it_suma` (презапис) + `discount_applied` | промо кодове |

Инвариант: `Phase1_suma = it_suma + discount_applied` (реконструируем; reset-then-apply е идемпотентен). `it_osnovna_cena` (Phase 0) служи за percent сравнението.

## Поведение

- **percent** → намалява всеки ред директно (`it_cena`/`it_suma`), compare-and-pick-lower срещу `it_osnovna_cena × (1 − %)` (артикул с по-голяма продуктова отстъпка пази своята). `discount_applied` следи делтата. Без отделен ред в UI — отстъпката е в цената.
- **fixed (ваучер)** → маха от общата сума: `min(discount_value, voucher_remainer, subtotal)`. Отделен ред показва колко е махнал. `voucher_remainer` намалява при потвърждаване.
- **shipping** → маха от доставката **динамично** (никаква запазена стойност); `pordost_coupon_discount` се пише за UI/анализ.
- **re-validate при cart CRUD** → при всяко прелистване/промяна кодовете се проверяват наново; невалидните (min_subtotal, изтекъл, изчерпан ваучер) отпадат автоматично.

## Управление на връзките (cross-DB)

Промо таблиците са **само в `imartap`** (споделена), cart таблиците (`item_l`/`item_no`) са per-site. По конвенцията на кода — **една активна връзка**, сменяна с close/reopen. Нов orchestrator `promo_recalc()` прави **точно 2 swap-а**: регионална (чете артикули) → imartap (промо логика) → регионална (записва Phase 2). `finally` гарантира restore (без leak при `exit`).

## Промени в кода

**Нови файлове:**
- `citte/lib/db-switch.php` — `emart_db_to_imartap()`, `emart_db_restore()`, `promo_recalc()`
- `citte/lib/PromoCalc.php` — чиста математика, без DB (percent/ваучер/доставка)
- `citte/lib/CartItems.php` — регионални item операции (`read`, `subtotal`, `applyItemDiscounts`)

**Променени:**
- `citte/lib/PromoCode.php` — само imartap; нови `revalidate()` + `persistCartDiscounts()`; махнати `applyCartDiscounts`/`applyShippingDiscount`/`getCartTotal`
- `citte/api/promo-cart.php`, `citte/api/promo-validate.php` — swap-обвити apply/remove/validate + `promo_recalc`
- `citte/case.php`, `citte/case_potv.php` — `promo_recalc` преди item read; ваучер/доставка редове; `pordost_coupon_discount` запис
- `citte/v_case.php` — `discount_applied='0'` при write на артикул (свеж Phase 1)
- `citte/podavam_za.php` — финализиране в imartap swap (ваучер+доставка+`finalizeForOrder`); `discount_applied` пътува в `item_l → item` copy
- `citte/promo-cart-rows.php` — при 'discount' показва само ваучер (percent е в артикула)

## DB миграции

`mysql-dumps/promo_codes/`:
- `08-add-phase2-columns.sql` — `discount_applied` на `item_l`/`item_no`/`item`; `pordost_coupon_discount` на `porachki`/`porachki_l`/`porachki_no`. Idempotent + table-existence safe (guarded чрез `information_schema`), таргетира `DATABASE()` → безопасно за всички региони.
- `09-drop-per-site-promo-tables.sql` — DROP на промо таблиците от per-site DBs (единен източник imartap). **Guard `DATABASE() <> 'imartap'`** → не пипа production кодовете.
- `10-verify-phase2.sql` — проверка колони + промо таблици.

Изпълнение (per region) през `emart-monorepo/packages/db/scripts/batch-sql-dbs/sql-batch-dbs.ts`.

## Проверено

- `PromoCalc` unit harness → **ALL PASS** (compare-and-pick-lower, ваучер cap, shipping cap, voucher > subtotal)
- Всички нови SQL заявки → изпълнени срещу реалната схема, валидни
- 11 PHP файла → lint clean
- Миграции 08/09 → idempotent (08 ран 2× clean); 09 не пипа imartap (промо кодовете остават)
- **Bug fix:** ваучер = `min(discount_value, voucher_remainer, subtotal)` — старата логика ползваше само `voucher_remainer` (FLAT5 щеше да маха 50 вместо 5 лв)

## Отложено

**Negative Микроинвест ред за ваучер.** `porach_suma` се намалява коректно с ваучера, percent е в артикулите, но няма отделен negative `item` ред → при ползван **ваучер** `SUM(item.it_suma)` (pre-voucher) ≠ `porach_suma`. Редът взаимодейства с copy-машинарията и free-shipping прага в `podavam_za.php` → отложен до staging тест. **Нужно потвърждение от @Ivo как Микроинвест ингестира реда.**

## Преди production

- [ ] Изпълни `08` (колони) + промо DDL на всички региони
- [ ] Изпълни `09` (drop per-site промо таблици) — само за регионалните, imartap е guarded
- [ ] Изтрий dev seed кодовете (TEST10/SUMMER20/FLAT5/FREESHIP)
- [ ] Staging end-to-end тест (app не е runnable локално: `zamysql.php` gitignored, `DOCUMENT_ROOT=./www`)
- [ ] Реши negative Микроинвест ред за ваучер с @Ivo

## Отворени въпроси

- **Free-shipping праг при ваучер** — изчислява се върху Phase-2 (post-percent, pre-voucher) subtotal. Да потвърдим.
- **Stacking на няколко percent кода** — каскадно; `stack_group` ограничава комбинациите.
