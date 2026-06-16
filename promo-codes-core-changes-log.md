# Промо кодове — 4 core промени от одита (issue #610)

Продължение след одита от 12.06.2026. Имплементират се 4-те неизпълнени code изисквания.
Пълна документация: [public_html/citte/docs/promo-codes-system.md](public_html/citte/docs/promo-codes-system.md).

**Scope:** само 4-те core промени (без UI extras / E2E / seeds-cleanup). Verification: `php -l` clean,
PromoCalc unit тестове, миграции срещу dev `imartap`, Микроинвест reconcile симулация.

---

## Промяна 1 — Percent: важи само най-високият код

**Изискване** (drago/Иво, 27.05): при 2+ percent кода се прилага само този с най-голям `discount_value`;
останалите остават в количката, но дават 0 — **НЕ** се инвалидират.

**Файл:** [public_html/citte/lib/PromoCalc.php](public_html/citte/lib/PromoCalc.php) — `compute()`, percent блокът.

**Преди:** `foreach` по всички percent редове, каскадно (всеки върху резултата на предходния).
**След:** избира се единственият percent ред с max `discount_value` (`$bestPercent`); прилага се само той
(per-item compare-and-pick-lower срещу `it_osnovna_cena`). За другите percent редове `per_promo[id]=0`.
При равенство печели първият (стабилно по реда от `getAppliedForCart`).

---

## Промяна 2 — Voucher burn + drop на `voucher_remainer`

**Изискване** (drago, 08.06): махане на цялата „save remainder" функционалност — ваучерът се изразходва
изцяло при употреба, без пренасян бюджет. Отстъпка per употреба = `min(discount_value, subtotal)`.
Повторна употреба се управлява само от `max_uses`/`times_used`. **Решение на потребителя:** drop на колоната.

**PHP:**
- [lib/PromoCalc.php](public_html/citte/lib/PromoCalc.php) — fixed блок: `min(value, subtotal)` (без `voucher_remainer` budget); docblock почистен.
- [lib/PromoCode.php](public_html/citte/lib/PromoCode.php):
  - `validate()` — `voucher_remainer` извън SELECT; махната „fixed budget exhausted" проверка.
  - `previewDiscount()` — fixed = `min(value, cartTotal)`.
  - `getAppliedForCart()` — `voucher_remainer` извън SELECT и връщания масив.
  - `revalidate()` — махнато fixed-budget drop условие.
  - `markUsed()` — махнат UPDATE-а, който намаляваше `voucher_remainer`.
- [the-marketer/promo-codes.php](public_html/citte/the-marketer/promo-codes.php) — `voucher_remainer` извън INSERT-а.

**Миграции** (`mysql-dumps/promo_codes/new/`):
- `01-create-promo_codes.sql` — колоната махната от CREATE (fresh install вече без нея).
- `05`/`06`-migrate — `voucher_remainer` извън INSERT-ите.
- `09-drop-voucher_remainer.sql` (НОВ) — guard-нат `ALTER ... DROP COLUMN` за бази мигрирани преди това; no-op за fresh.
- `11-verification.sql` — schema sanity добавя „NO voucher_remainer (burned)" → очаквано 0.
- README + номерация: verification → 11/12.

**Тест seed** [api/promo-validate-table.sql](public_html/citte/api/promo-validate-table.sql) — махнат `voucher_remainer` от CREATE + FLAT5 UPDATE-а.

**Док:** [citte/docs/promo-codes-system.md](public_html/citte/docs/promo-codes-system.md) — речник, логика, валидации, методи.

---

## Промяна 3 — Микроинвест negative ред за `fixed` (ваучер/купон)

**Изискване** (drago 27.05 + договорка 28.05): fixed отстъпката стига до Микроинвест като отделен ред.
`percent` е вече в цените (без ред); `shipping` минава през `cendost`/`pordost_coupon_discount` (готово).
Значи **само fixed** иска negative ред.

**Подход (Option B — finalize-time):** запазваме сегашния deduction за тоталите и **добавяме** negative
`item` ред при финализиране. Реконсилиация: `SUM(item.it_suma) = porach_suma` (`bpbp_sum` вече е намален
с ваучера) → без двойно броене. Verified в dev (80 продукти − 5 ваучер = 75 = porach_suma).

**Файлове:**
- [lib/db-switch.php](public_html/citte/lib/db-switch.php) — нова константа `PROMO_FIXED_CAT_NO` (default `'5555555'`) + helper `promo_micro_voucher_row($conn, $orderId, $amount, $potrId, $ip)` (INSERT negative `item` ред; no-op при `amount<=0`).
- [podavam_za.php](public_html/citte/podavam_za.php) — извикване в двата finalize пътя (логнат + гост), по веднъж за всяка връзка (regional + imartap), огледално на mirror-натия `UPDATE porachki`. Master `item` е в imartap (ред 221-222) + реплика в регионалната база.
- `mysql-dumps/promo_codes/new/10-catalog-promo-skus.sql` (НОВ) — seed на промо SKU продукти в `catalog` (5555555/6666666/7777777/8888888, `cena=0`), guard по table existence (no-op за imartap).

**PENDING drago:** (a) fixed SKU — 5555555 (Ваучер) vs 7777777 (Купон), понеже схемата ги слива; (b) `prioritet_micro` и метадата на реда ползват неутрални defaults — да се сверят с реалната ingestion. Сменя се с 1 константа.

---

## Промяна 4 — Fix на счупения промо блок в `case_ptvd.php`

**Бъг:** [case_ptvd.php](public_html/citte/case_ptvd.php) викаше несъществуващи `applyCartDiscounts()` (328)
и `applyShippingDiscount()` (446), инстанцираше `PromoCode` без swap към imartap, без `promo_recalc()` → fatal.

**Откритие:** файлът е **order-confirmation** (чете финализирана `item` по `$petel`), НЕ количка.
`cart_promo_codes` вече е изчистена (от `finalizeForOrder`), а отстъпките са вече в item редовете
(percent в цените; ваучер като negative ред от Промяна 3; shipping в `cendost`). Затова recompute е
концептуално грешен тук.

**Fix:** премахнат целият счупен recompute блок; `$_cartDiscount`/`$_shipDiscount` = 0 (отстъпките вече
са отразени в `$obshto_sum` и `$sumdosti`). Премахнатите `promo-cart-rows.php` include-ове разчитаха на
празен `$_promoRows`. Ваучерът се показва като negative item ред в обичайния item loop.

---

## Verification (dev docker `lamp-mysql8`, root/tiger)

| Проверка | Резултат |
|---|---|
| `php -l` на 6-те пипнати файла | ✅ No syntax errors |
| PromoCalc unit (pick-highest + voucher burn + shipping cap) | ✅ 10/10 PASS |
| `new/09-drop-voucher_remainer` срещу dev imartap | ✅ колоната падна; re-run no-op |
| Fresh full `new/` set (01→12) | ✅ 16,235 реда, без `voucher_remainer`; `11-verification` чисто |
| `new/10-catalog-promo-skus` (inmarta/imartap/iimarta) | ✅ inmarta получи 4 SKU; imartap/iimarta no-op (няма catalog) |
| Микроинвест reconcile (negative ред симулация) | ✅ `SUM(item.it_suma)=75=porach_suma` |
| Pick-highest unit (10%+20%) | ✅ важи 20% (30 лв.), 10% носи 0 |
| Voucher burn unit (fixed 5: subtotal 3→3, subtotal 100→5) | ✅ без budget cap |

**Файлове пипнати:** `lib/PromoCalc.php`, `lib/PromoCode.php`, `lib/db-switch.php`,
`the-marketer/promo-codes.php`, `podavam_za.php`, `case_ptvd.php`, `api/promo-validate-table.sql`,
`mysql-dumps/promo_codes/new/{01,05,06,09,10,11,README}`, `citte/docs/promo-codes-system.md`.

## За production / staging
- [ ] **PENDING drago:** потвърди fixed SKU (5555555 vs 7777777) → `PROMO_FIXED_CAT_NO`.
- [ ] Сверù `prioritet_micro` + метадата на negative реда с реалната Микроинвест ingestion.
- [ ] Изпълни `new/09` (drop voucher_remainer) + `new/10` (catalog SKUs) на staging/prod.
- [ ] E2E на staging: ваучер поръчка → провери negative ред в `item` и в Микроинвест; 2 percent кода → важи по-високият.

---
---

# Продължение (12.06.2026) — iron-clad фази + запазване на промо при мутация/login

## Промяна 5 — Iron-clad 3-фазен модел (`it_*_baza` колони)

**Проблем:** Phase 1 (най-ниска `cenni()`, преди промо) се **деривираше** като `it_suma + discount_applied`.
Чупеше се: cart writer ([v_case_actl.php](public_html/citte/v_case_actl.php) и др.) пренаписва `it_suma` от
`cenni()` при смяна на количество, **без** да нулира `discount_applied` → реконструкцията на Phase 1 е
грешна → грешна крайна цена след recalc.

**Решение:** изнасяме Phase 1 в **собствени frozen колони** `it_cena_baza` / `it_suma_baza`.
```
Phase 0  it_osnovna_cena              (каталог)
Phase 1  it_cena_baza / it_suma_baza  (НОВИ, frozen cenni — authoritative)
Phase 2  it_cena / it_suma            (след промо → Микроинвест)
audit    discount_applied = baza - it_suma   (само percent)
```

**Файлове:**
- Миграция `mysql-dumps/promo_codes/new/13-add-baza-columns.sql` (НОВ) + `old/12-add-baza-columns.sql` (НОВ, идентичен) — guarded/idempotent ALTER на `item_l`/`item_no`/`item` + backfill (`baza = it_suma + discount_applied`).
- 5 Phase-1 writers ([v_case.php](public_html/citte/v_case.php), [v_case_actl.php](public_html/citte/v_case_actl.php), [v_case_actli.php](public_html/citte/v_case_actli.php), [v_casekuk.php](public_html/citte/v_casekuk.php), [v_cases.php](public_html/citte/v_cases.php)) — пишат `it_cena_baza`/`it_suma_baza` + `discount_applied=0`.
- [lib/CartItems.php](public_html/citte/lib/CartItems.php) — `read()`/`subtotal()` четат Phase 1 от `baza` (COALESCE fallback към стария derived вид за deploy-window).
- [podavam_za.php](public_html/citte/podavam_za.php) — `baza` колони в 4-те `item_l`/`item_no`→`item` copy блока.

**Bonus fix (намерен при copy блоковете):** guest finalize беше **счупен** — INSERT 27 cols vs 26 values
(`showerror1`=`exit`) → guest поръчка с артикули гърмеше; и `discount_applied` не стигаше до `item` за
гости (percent невидим за Микроинвест). И двете оправени (29=29, `discount_applied` се SELECT-ва).

---

## Промяна 6 — Запазване на промокоди при cart-мутация + login (ГАП 1, PHP-only)

**Проблем:** `promo_recalc()` се викаше само на [case.php:31](public_html/citte/case.php#L31),
[case_potv.php:220](public_html/citte/case_potv.php#L220), [api/promo-cart.php](public_html/citte/api/promo-cart.php).
**7 мутиращи пътя** (add/qty/remove/repeat/cookie/login-merge/`case_pdacl` re-price) НЕ викаха recalc →
writer-ите пренаписваха реда на Phase 1 + `discount_applied=0` → промото "изчезваше" от `item_l`
(mini-cart [header.php:329](public_html/citte/header.php#L329) показва недисконтирана цена) до следващо
зареждане на количката. Отделно: при login [v_case_preh.php](public_html/citte/v_case_preh.php) слива
гост-количката (`item_no`→`item_l`) но **не мигрираше** `cart_promo_codes` → промото на госта се губеше.

**Решение A (re-apply след мутация):** флаг `$_cartMutated` в 6-те мутиращи trigger-а
([index.php](public_html/index.php): case_pdacl/v_case/v_case_preh/v_cases/cookie + [sesii.php:557](public_html/citte/sesii.php#L557) remove)
+ **единичен идемпотентен `promo_recalc`** в index.php след writer блока (преди рендера). Всички 7 мутации
са full-page POST през index.php (qty/add форми в [myn.js](public_html/scripts/myn.js) са form submit, не AJAX) → 1 точка покрива всичко.

**Решение B (login миграция):** нов [PromoCode::migrateCart()](public_html/citte/lib/PromoCode.php)
(`UPDATE IGNORE` re-key + `DELETE` leftover; конфликт → пази логнатия код) + swap-helper
[promo_migrate_cart()](public_html/citte/lib/db-switch.php) в db-switch. Извиква се в index.php login-блока
(`$vcasepreh`) — мигрира `cart_promo_codes` (`$tuksus`,'no')→(`$pe`,'l') **преди** recalc, който после ги прилага.

**Файлове:** `index.php`, `citte/sesii.php`, `citte/lib/PromoCode.php`, `citte/lib/db-switch.php`. Без схема/миграция.

---

## Verification (доп., dev docker `lamp-mysql8`, root/tiger)

| Проверка | Резултат |
|---|---|
| `php -l` (5 writers, CartItems, podavam_za, index, sesii, PromoCode, db-switch) | ✅ clean |
| Миграция `new/13` + `old/12` (imartap/inmarta/iimarta) | ✅ runs; idempotent (re-run exit 0); backfill 49962 реда (0 null); guards OK (iimarta без item → no-op) |
| **Desync regression** (qty change с активен percent) | ✅ FIXED — `it_suma_baza` пази Phase 1; крайна цена коректна |
| Guest finalize column/value | ✅ 27→**29 cols = 29 values** (mismatch оправен) |
| `migrateCart` SQL вкл. конфликт | ✅ гост код мигрира; конфликтен код пази логнатата стойност; гост-редове изчистени (transaction ROLLBACK) |

**Файлове пипнати:** `lib/CartItems.php`, `lib/PromoCode.php`, `lib/db-switch.php`, `podavam_za.php`,
`v_case.php`, `v_case_actl.php`, `v_case_actli.php`, `v_casekuk.php`, `v_cases.php`, `index.php`, `sesii.php`,
`mysql-dumps/promo_codes/new/{13,README}`, `mysql-dumps/promo_codes/old/12`.

## За production / staging (доп.)
- [ ] **Ред на deploy:** изпълни `new/13` (или `old/12` за old-path среди) **ПРЕДИ** PHP deploy — writer-ите четат `baza` колоните; стар код срещу нова схема е OK, нов код срещу стара схема гърми (unknown column).
- [ ] E2E: **guest** поръчка с артикули → finalize минава (беше счупено) + percent `discount_applied` стига до `item`.
- [ ] E2E: приложи percent → смени количество → промото се запазва (item_l пак Phase 2).
- [ ] E2E: гост приложи промо → впиши се → кодът мигрира към логнатата количка.
- [ ] (по избор) finalize safety recalc в podavam_za; fixed видим в mini-cart; cenni Phase-1 refresh на render — известни остатъчни ГАП-ове, не в обхвата.

---
---

# Продължение (13.06.2026) — Q1 регионални пивоти + Q3 `shipping_percent`

План: `.claude/plans/velvety-strolling-backus.md`. Одит изводи: Q1 (таблици) грешно разбран —
и трите бяха в imartap; Q2 потвърден коректен (без промени); Q3 — `shipping` вече покрива
full/flat, липсва само процент.

## Промяна 7 — Storage split (Q1): пивотите → регионални, каталогът остава imartap

**Решение (drago):** `promo_codes` = една таблица в `imartap` (каталог); `cart_promo_codes` +
`order_promo_codes` се местят в регионалните бази (до количката). Сега само **inmarta**;
другите региони ръчно по-късно.

**Подход:** пивотите се четат/пишат на **регионалната (текущата) връзка** — всички imartap
connection-swap-ове за промо премахнати. Каталогът се чете квалифицирано `imartap.promo_codes`
(нова константа `PROMO_CATALOG_DB` в [db-switch.php](public_html/citte/lib/db-switch.php)).
Един MySQL инстанс → cross-schema JOIN работи (dev root; prod иска GRANT на регионалния user).

**PHP файлове:**
- [lib/db-switch.php](public_html/citte/lib/db-switch.php) — `PROMO_CATALOG_DB`; `promo_recalc()` и
  `promo_migrate_cart()` без swap (вървят изцяло регионално); header docblock обновен. `*Var` params
  запазени за call-site compat (no-op).
- [lib/PromoCode.php](public_html/citte/lib/PromoCode.php) — каталог референции квалифицирани
  `PROMO_CATALOG_DB.promo_codes` (validate SELECT + stack subquery, getAppliedForCart JOIN, markUsed
  UPDATE); пивотите неквалифицирани (регионални); self-contained const guard; docblock „IMARTAP-ONLY" → split.
- Inline swap-ове махнати (вървят на регионалната връзка): [case.php](public_html/citte/case.php),
  [case_potv.php](public_html/citte/case_potv.php), [podavam_za.php](public_html/citte/podavam_za.php)
  (2 finalize пътя), [api/promo-cart.php](public_html/citte/api/promo-cart.php) (list/apply/remove),
  [api/promo-validate.php](public_html/citte/api/promo-validate.php).

**Миграции** (`mysql-dumps/promo_codes/new/`):
- `14-create-cart_promo_codes-regional.sql` + `15-create-order_promo_codes-regional.sql` (НОВИ) —
  CREATE в регионалната база, **без** cross-DB FK; `CREATE TABLE IF NOT EXISTS` (safe срещу imartap).
- `08-drop-per-site-promo-tables.sql` — **поправена**: вече трие само per-site `promo_codes`; пивотите
  cart/order НЕ се трият (вече регионални).

**Известни/отложени:** prod GRANT `SELECT,UPDATE ON imartap.promo_codes` за регионалния user; data-миграция
на историята `imartap.order_promo_codes` → региони; другите региони (само inmarta мигрирана).

## Промяна 8 — нов промо тип `shipping_percent` (Q3): процент от доставка

`shipping` вече дава full (`shipping_cap=NULL`) и flat (`shipping_cap=X`). Добавен `shipping_percent`:
`discount_value`=процент, `shipping_cap`=опционален таван (лв). Отстъпка = `fullShipping*%`, capped до
cap и до остатъка; намалява `cendost` към Микроинвест, без negative item ред (огледално на `shipping`).

**Файлове:**
- [lib/PromoCalc.php](public_html/citte/lib/PromoCalc.php) — нов `shipDiscountForRow()` (единна shipping
  математика); `compute()` + `shippingDiscount()` минават през него; филтър по
  `['shipping','shipping_percent']`.
- 4-те inline shipping loop-а ([case.php], [case_potv.php], [podavam_za.php] ×2) → викат helper-а
  (обединено с Промяна 7 в същите блокове), `fullCost` = `$sumdosti`/`$cendost_op`.
- [lib/PromoCode.php](public_html/citte/lib/PromoCode.php) `previewDiscount()` — `'shipping_percent'=>0.0`.
- Display: [promo-cart-rows.php](public_html/citte/promo-cart-rows.php),
  [promo-input.php](public_html/citte/promo-input.php) — третират percent като shipping.
- [the-marketer/promo-codes.php](public_html/citte/the-marketer/promo-codes.php) typeMap `3=>'shipping_percent'`.
- Миграция `16-add-shipping_percent-type.sql` (НОВА) — ENUM на `promo_codes` + `cart_promo_codes`;
  guard по COLUMN_TYPE, idempotent.

## Verification (dev docker `lamp-mysql8`, root/tiger; php herd-lite)

| Проверка | Резултат |
|---|---|
| `php -l` на 11-те пипнати файла | ✅ clean |
| `new/14`,`new/15` срещу inmarta | ✅ пивотите създадени, **0 FK**; idempotent re-run без ERROR |
| `new/16` срещу imartap + inmarta | ✅ ENUM съдържа `shipping_percent` (3 таблици); re-run no-op |
| `new/08` срещу inmarta | ✅ cart/order пивоти **оцеляват** |
| Cross-schema JOIN `inmarta.cart_promo_codes` × `imartap.promo_codes` | ✅ връща `discount_value`/`active` (getAppliedForCart shape) |
| Unit `shipDiscountForRow` (7 кейса: percent/cap/remaining/full/flat/0/other) | ✅ 7/7 PASS |

**За production / staging:** изпълни `new/14`+`new/15` за всеки регион **преди** PHP deploy за него;
GRANT на регионалния user към `imartap.promo_codes`; `new/16` срещу imartap + всички региони; E2E
inmarta (apply→recalc→finalize: ред в `inmarta.cart/order_promo_codes` + `imartap.promo_codes.times_used`++;
`shipping_percent` код → доставка пада с %).

---
---

# Продължение 2 — остатъчни ГАП-ове + Q1 cleanup + Микроинвест percent решение

## ГАП 5 — finalize safety recalc
[podavam_za.php](public_html/citte/podavam_za.php) — `promo_recalc` непосредствено преди `item_l`/`item_no`→`item`
copy (логнат + гост). Гарантира прясно Phase-2 промо при поръчка (case_potv recalc-ва при display, това — при submit).

## ГАП 2 — cenni Phase-1 staleness (на checkout)
[case_potv.php](public_html/citte/case_potv.php) — `require case_pdacl.php` (re-price всички cart редове от `cenni()`)
ПРЕДИ `promo_recalc`. Клиентът вижда текущи каталожни цени преди да потвърди. Cart-browse (case.php) остава
add-time цена (козметично). case_pdacl нулира `discount_applied`+пише `baza`; recalc-ът после връща Phase 2.

## ГАП 3 — fixed невидим в mini-cart
fixed е order-level (не ред в item_l), затова [header.php](public_html/citte/header.php) `SUM(it_suma)` го пропускаше.
- Миграция **new/17** (= old/13): `promo_fixed_discount` на `porachki_l`/`porachki_no`.
- [lib/db-switch.php](public_html/citte/lib/db-switch.php) `promo_recalc` (Phase B) — пише fixed-тотала в cart-header (регионален UPDATE; no-op ако ред няма).
- [header.php](public_html/citte/header.php) — mini-cart вади колоната (logged 329 + guest 369). Логнат → пълно (porachki_l съществува при browse); гост → след address стъпка (porachki_no се създава в case_dopl_no_zap).

## Q1 cleanup — `cart_promo_codes` махнат от imartap
Q1 (паралелен рефактор) премести пивотите в регионалната база. Остана legacy `cart_promo_codes` в imartap.
- **new/18-drop-imartap-cart_promo_codes.sql** (НОВ) — guarded `DROP TABLE IF EXISTS cart_promo_codes` (само `DATABASE()='imartap'`). Transient таблица → без загуба на данни. Пуска се СЛЕД new/14. Verified на dev: imartap drop-нат, inmarta оцелял, re-run idempotent.
- `order_promo_codes` (история) **НЕ** е drop-нат — иска data миграция (отделно).
- Numbering: моят promo_fixed_discount беше 14, преномериран на **17** (Q1 зае 14/15/16). README: 02/03 маркирани LEGACY.
- **old-path deploy fix:** old/ беше Q1-непълен (само new/ имаше регионалните create-и) → drop там чупеше. Добавени **old/14** (регионален cart_promo_codes), **old/15** (регионален order_promo_codes), **old/16** (shipping_percent), **old/17** (drop imartap cart) — копия на new/14/15/16/18. old/ вече е self-contained: drop (17) **след** create (14) → безопасно по ред. Verified последователност на dev: imartap cart=0 (create→drop), order=1 (preserved), inmarta cart+order=1.

## Микроинвест — percent отстъпка: НЕТНА цена (решение на потребителя)
Микроинвест importer-ът **НЕ чете** `discount_applied`/`it_osnovna_cena`. Решение: **percent отива като нетна
`it_cena`/`it_suma`; БЕЗ отделен ред, БЕЗ атрибуция на отстъпката в Микроинвест.** `discount_applied` остава
само вътрешен audit (cart UI/математика). (fixed → negative ред 5555555; shipping → `cendost`.)
→ **Коригира** по-раншната бележка „percent видим през per-ред `discount_applied`" — де факто Микроинвест не го чете.

## Verification
- `php -l` чисто: case_potv.php, podavam_za.php, lib/db-switch.php, header.php.
- Миграции 17/18 + old/13: runs, idempotent; drop verified (imartap=0, inmarta=1); guard срещу регион = no-op.
- ГАП 3 round-trip: `promo_recalc` UPDATE → header SELECT връща стойността.

**Файлове:** `case_potv.php`, `podavam_za.php`, `lib/db-switch.php`, `header.php`,
`mysql-dumps/promo_codes/new/{17,18,README}`, `mysql-dumps/promo_codes/old/13`.

## Остатъчни (по избор)
- Guest mini-cart fixed: пълно чак след address стъпка (porachki_no).
- cenni Phase-1 refresh на cart-browse (case.php) — само checkout сега.
- `order_promo_codes` imartap→regional data миграция (Q1 довършване).
