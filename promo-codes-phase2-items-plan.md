# План: Phase 2 промо отстъпки "вътре в артикула" + Микроинвест редове

## Контекст

Промо-системата (`promo_codes` / `cart_promo_codes` / `order_promo_codes`) е мигрирана и работи, но прилага отстъпката **само display-time**: `case_potv.php:703,846` смята `subtotal − cart_discount` и никога не пипа `it_cena`/`it_suma`. Поръчките отиват към **Микроинвест**, който чете line-level цените от таблицата `item` — той не вижда `cart_promo_codes`, така че промо отстъпката е невидима за него.

Решихме отстъпката да живее **вътре в артикула**. Три фази на цената; Phase 2 (промо) се **записва** върху `it_cena`/`it_suma` per артикул с audit колона `discount_applied`; ваучер и купони за доставка добавят отделен ред, който показва колко са махнали; доставката се смята **динамично** с колона `pordost_coupon_discount`.

## Решения

1. **Phase 2 модел:** презапис на `it_cena`/`it_suma` + нова audit колона `discount_applied` (чисто audit, 0 business logic). Заменя сегашния display-only subtotal подход.
2. **Микроинвест ред:** един negative ред във финалния `item` при финализиране, **само за `fixed` (ваучер) и `shipping`** типове. `percent` промото вече е в `it_cena` per артикул, не му трябва отделен ред.
3. **Ваучер семантика:** ваучерът маха от **общата цена** (subtotal), не per артикул. Слагаме ред, който показва колко пари е махнал ваучерът.
4. **Cross-DB:** единен източник `imartap` за трите промо таблици; `item`/`porachki` таблиците остават per-site.
5. **Управление на връзките:** една активна mysqli връзка по конвенцията на кода (`podavam_za.php` вече swap-ва ~30 пъти close/reopen). Промо методите (imartap) се викат само докато imartap връзката е отворена: затваряме регионалната → отваряме imartap → работа → затваряме imartap → отваряме регионалната обратно. Без две едновременни връзки.

## Трите фази

| Фаза | Носител | Източник | Файл |
|---|---|---|---|
| 0 | `it_osnovna_cena` | `catalog.cena × koeffvalutt` | `v_case.php:267` |
| 1 | `it_cena` / `it_suma` | `cenni()` — меню/количествени/продуктови отстъпки | `v_case.php:278-279` |
| 2 | `it_cena` / `it_suma` (презапис) + `discount_applied` | промо (percent per артикул; ваучер/доставка — отделен ред) | НОВО |

**Инвариант за идемпотентност:** `Phase1_it_suma = it_suma + discount_applied`. Винаги reset до Phase 1 преди да приложим Phase 2 наново. Phase 0 (`it_osnovna_cena`) остава непокътнат и служи за percent сравнението.

---

## Стъпка 0 — Управление на връзките (imartap ↔ регионална)

### Топология (карта на връзките)

| Файл | Активна връзка на страницата | Промо четения днес |
|---|---|---|
| `case.php:96-97`, `case_potv.php:359-363` | `$msql_basap` (primary) | на същата връзка |
| `api/promo-cart.php:13`, `api/promo-validate.php:22` | per-site `${$msqbasa}` (`msql_<region>basa`) | на същата връзка |
| `podavam_za.php` | swap-ва между `$msql_basap` и per-site ~30 пъти | в per-site блок |
| `zipchat.php:10` | — | отделна `mysqli_connect($msql_hostp,$msql_portp,$msql_passp,'imartap')` |

**Следствие:** след като промо таблиците станат само в imartap (решение 4), нито една от тези активни връзки не гарантирано сочи imartap → всяко промо четене/писане трябва да е обвито в swap към imartap и обратно.

> **Да се потвърди (блокиращо):** дали `$msql_basap` == `imartap`. Ако да — в `case.php`/`case_potv.php` промо ops вече са на imartap и swap там не е нужен; ако не — нужен е навсякъде. Helper-ите по-долу работят и в двата случая (явен restore target).

### Две helper функции (нов файл `citte/lib/db-switch.php`)

Идиомът от `podavam_za.php` (close + reopen + `SET NAMES`), извлечен в две функции с `&$connection` (за да се обнови променливата на викащия):

```php
// затваря текущата, отваря imartap
function emart_db_to_imartap(&$connection) {
    @mysqli_close($connection);
    $connection = mysqli_connect($GLOBALS['msql_hostp'], $GLOBALS['msql_portp'], $GLOBALS['msql_passp'], 'imartap')
        or die("Could not connect");
    mysqli_query($connection, "SET NAMES 'utf8';");
}

// затваря imartap, отваря базата с подадените *имена* на globals (restore точно към тази, която викащият е ползвал)
function emart_db_restore(&$connection, string $hostVar, string $portVar, string $passVar, string $basaVar) {
    @mysqli_close($connection);
    $connection = mysqli_connect($GLOBALS[$hostVar], $GLOBALS[$portVar], $GLOBALS[$passVar], $GLOBALS[$basaVar])
        or die("Could not connect");
    mysqli_query($connection, "SET NAMES 'utf8';");
}
```

### Контракт за PromoCode (избягва stale handle)

Вместо PromoCode да държи две връзки или да swap-ва вътрешно, **разделяме отговорностите** така, че всеки клас да пипа само една база, а викащият да swap-ва около тях:

- **`PromoCalc` (чист PHP, без DB)** — `compute($rows, $items, $shippingCost)` → връща per-item отстъпки + cart/shipping суми. Тестваем без база.
- **`PromoCode` (само imartap)** — `getAppliedForCart / validate / revalidate / persistCartDiscounts / markUsed / finalizeForOrder`. Инстанцира се **след** swap към imartap; кратко живуща; не преживява swap.
- **`CartItems` (само регионална)** — `read($conn, …)`, `applyItemDiscounts($conn, $plan, …)` върху `item_l`/`item_no`.

PromoCode никога не затваря/отваря връзка сам → няма stale handle. Swap-ът е явен в orchestrator-а (стъпка 2б).

---

## Стъпка 1 — DB миграции

### 1а. Нови колони (per-site DBs + imartap, понеже `item`/`porachki` са и на двете)

```sql
ALTER TABLE item_l    ADD COLUMN discount_applied DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT 'Phase 2 промо отстъпка на реда (audit)';
ALTER TABLE item_no   ADD COLUMN discount_applied DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT 'Phase 2 промо отстъпка на реда (audit)';
ALTER TABLE item      ADD COLUMN discount_applied DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT 'Phase 2 промо отстъпка на реда (audit)';

ALTER TABLE porachki    ADD COLUMN pordost_coupon_discount DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT 'Отстъпка от доставка промо (audit/UI)';
ALTER TABLE porachki_l  ADD COLUMN pordost_coupon_discount DECIMAL(10,2) NOT NULL DEFAULT 0.00;
ALTER TABLE porachki_no ADD COLUMN pordost_coupon_discount DECIMAL(10,2) NOT NULL DEFAULT 0.00;
```

Изпълняваме през съществуващия batch tool: `emart-monorepo/packages/db/scripts/batch-sql-dbs/sql-batch-dbs.ts` (паттернът е описан в `promo-code-migration-log.md`). Прилага се на всички региони + imartap.

### 1б. Промо таблиците → единен източник imartap

- `promo_codes`, `cart_promo_codes`, `order_promo_codes` остават **само в imartap** (вече има 16,235 реда там).
- `DROP` на трите таблици от per-site DBs (inmarta/iimarta/almarta…) — обръщаме частично Step 9 от стария план.
- `cart_promo_codes.cart_id` продължава да реферира per-site `porachki_id`/`sesii_id` като число (без cross-DB FK — FK-ите остават само вътре в imartap).

---

## Стъпка 2 — Phase 2 writer + orchestrator със swap

### 2а. Orchestrator `promo_recalc()` — единната точка, **точно 2 swap-а**

Свободна функция (в `db-switch.php` или `PromoCode.php`), приема `&$connection` и имената на globals на текущата (регионална/primary) база, за да я възстанови накрая. Викащият подава къде да се върне → topology-agnostic. Идемпотентна; извиква се на всяка промяна (cart CRUD, apply/remove, render, finalize):

```
promo_recalc(&$connection, $cartId, $cartType, $po, $shippingCost,
             $hostVar,$portVar,$passVar,$basaVar):

  # ── ФАЗА A: регионална (текущата връзка) ──────────────────
  items = CartItems::read($connection, $cartId, $cartType)   # SELECT item_l/item_no
  # RESET до Phase 1 (идемпотентност): phase1_suma = it_suma + discount_applied
  CartItems::resetToPhase1($connection, $cartId, $cartType)  # UPDATE ... it_suma+=discount_applied, discount_applied=0

  # ── SWAP 1 → imartap ──────────────────────────────────────
  emart_db_to_imartap($connection)
  $promo = new PromoCode($connection)
  rows = $promo->getAppliedForCart($cartId, $cartType)
  $promo->revalidate(rows, items, $cartId, $cartType)   # невалидните → DELETE cart_promo_codes
  plan = PromoCalc::compute(rows, items, $shippingCost)  # чист PHP, без DB
  $promo->persistCartDiscounts(rows, plan, $cartId, $cartType)  # UPDATE cart_promo_codes.discount_applied

  # ── SWAP 2 → обратно към регионалната ─────────────────────
  emart_db_restore($connection, $hostVar,$portVar,$passVar,$basaVar)
  CartItems::applyItemDiscounts($connection, plan, $cartId, $cartType)  # UPDATE item_l/item_no

  return plan   # [cart_discount, shipping_discount] за display + pordost_coupon_discount
```

Точно **2 swap-а** на извикване (не per-query), защото DB достъпът е групиран по база: всички регионални четения първо, после целият imartap блок, после регионалните записи. Завършва на регионалната — викащият продължава безпроблемно.

### 2б. `PromoCalc::compute()` — чистата логика (без DB)

```
compute(rows, items, shippingCost):
  1. PERCENT (per артикул, compare-and-pick-lower):
       u1 = phase1_suma/item_br; promo_u = it_osnovna_cena*(1-pct/100)
       eff_u = (it_osnovna_cena>0) ? min(u1, promo_u) : ROUND(u1*(1-pct/100),2)
       line_disc = phase1_suma - eff_u*item_br   → plan.items[id]
  2. FIXED (ваучер, cart-level): disc = min(voucher_remainer, subtotal_след_percent)  → plan.cart
  3. SHIPPING: ship_disc = (shipping_cap===null) ? shippingCost : min(cap, shippingCost) → plan.shipping
  return plan
```

Percent преди fixed (ваучерът смята върху вече намаления subtotal). Старата dead per-item логика (`PromoCode.php:178-193`) и `calculateCartDiscount` се пренасят тук. `applyCartDiscounts`/`applyShippingDiscount` отпадат — заменени от orchestrator + PromoCalc.

---

## Стъпка 3 — Integration points

> Всеки entry point подава на `promo_recalc()` имената на globals за **своята** текуща база (restore target), за да се върне точно там, откъдето е тръгнал.

### 3а. Cart CRUD — `v_case.php` (add/update/remove)
- Към INSERT/UPDATE на `item_l`/`item_no` (`v_case.php:278-321`) добавяме `discount_applied = '0'` (свеж Phase 1 → нулирана отстъпка, иначе reset във ФАЗА A ще брои двойно).
- След записа: `promo_recalc(&$connection, …, restore→текущата на v_case)`. (Да се сверят имената на connection globals в v_case — там няма явен `mysqli_connect`, връзката идва от include.)
- Същото за пътищата за изтриване/смяна на количество (бутоните `pluskolata`/`minuskolata`/премахване).

### 3б. Apply / remove промо — `api/promo-cart.php` (връзка = per-site `${$msqbasa}`)
- INSERT/DELETE в `cart_promo_codes` сега са imartap ops → обвиваме ги в swap (или ги местим вътре в `promo_recalc`/`PromoCode`): `emart_db_to_imartap` → validate + insert/delete → `emart_db_restore(…, 'msql_'.$zuttrttuz.'host', …)`.
- `getCartTotal` (чете `item_l`/`item_no`) остава **преди** swap-а (регионална).
- След apply/remove → `promo_recalc()` с restore към per-site.

### 3в. Render — `case_potv.php:686-854` и `case.php` (връзка = `$msql_basap`)
- Заменяме двата отделни `applyCartDiscounts`/`applyShippingDiscount` извиквания с `promo_recalc(&$connection, …, restore→'msql_basap','msql_hostp',…)`.
- `it_cena`/`it_suma` вече са крайни (Phase 2) → редовете на артикулите показват намалените цени директно.
- Добавяме display ред за ваучера (PromoCalc стъпка 2) и за доставка отстъпката (стъпка 3) — `promo-cart-rows.php` вече рендира `discount_applied`; добавяме "колко махна ваучерът" ред.
- Доставка: смята се **динамично** всеки път (без stored стойност); резултатът пишем в `pordost_coupon_discount`.
- *(Ако се потвърди `$msql_basap == imartap` → тук swap не е нужен, само промо ops директно.)*

### 3г. Финализиране — `podavam_za.php:186-321`
- Преди копирането `item_l → item` извикваме `promo_recalc()`, за да са артикулите в краен Phase 2 вид (percent вече е в `it_cena`/`it_suma`/`discount_applied`, които текат натурално в `item` чрез съществуващия SELECT на ред 188 — добавяме `discount_applied` към колоните). Внимание: вмъква се **сред** съществуващите ~30 swap-а на файла → след `promo_recalc` връзката трябва да е там, където следващият блок очаква (виж картата на swap-овете: ред 283 per-site, ред 311 промо блок, ред 318 UPDATE porachki).
- `getAppliedForCart`/`applyCartDiscounts`/`finalizeForOrder` на ред 312-321 (logged) и 992-1000 (guest) вече трябва да се изпълнят докато **imartap** е активна, не per-site → пренасяме ги в imartap блок (swap), после restore.
- **Negative Микроинвест ред (само fixed/shipping):** след основния item INSERT loop, за всеки `fixed`/`shipping` промо с `discount_applied>0` вмъкваме един ред в master `item`:
  `cat_no` = конфигурируем промо SKU, `ime` = "Промо: <code>", `item_br=1`, `it_cena = -disc`, `it_suma = -disc`, `it_osnovna_cena=0`, `prioritet_micro` по конфиг, `no_nal='1'`. Репликата `item→item` (`podavam_za.php:232-254`) го взима автоматично.
- **Праг за безплатна доставка:** изчисляваме го върху Phase-1 subtotal (преди промо/ваучер), за да не губи клиентът free shipping заради ваучера → SUM(it_suma) за прага трябва да **изключва** negative промо редовете (филтър по промо SKU маркер). Виж Open items.
- `cendost` намалена с shipping отстъпката; пишем `pordost_coupon_discount` в `porachki`.
- `finalizeForOrder()` (markUsed → `order_promo_codes`, `times_used++`, `voucher_remainer` намаление) остава както е (`PromoCode.php:245-283`).

---

## Файлове за промяна

- **`public_html/citte/lib/db-switch.php`** (НОВ) — `emart_db_to_imartap(&$conn)` + `emart_db_restore(&$conn,…)` + orchestrator `promo_recalc()`.
- **`public_html/citte/lib/PromoCode.php`** — само imartap ops; `revalidate`, `persistCartDiscounts`; `getCartTotal` излиза към `CartItems`; пренасяне на `calculateCartDiscount` → `PromoCalc`.
- **`public_html/citte/lib/PromoCalc.php`** (НОВ) — чист PHP `compute()`, без DB.
- **`public_html/citte/lib/CartItems.php`** (НОВ) — регионални `read`/`resetToPhase1`/`applyItemDiscounts` върху `item_l`/`item_no`.
- **`public_html/citte/v_case.php`** — `discount_applied='0'` при write + `promo_recalc()` след CRUD.
- **`public_html/citte/api/promo-cart.php`** — swap-обвити apply/remove + `promo_recalc()` (restore→per-site).
- **`public_html/citte/case_potv.php`** и **`case.php`** — `promo_recalc()` вместо display-only (restore→`msql_basap`); ваучер/доставка display редове; `pordost_coupon_discount` запис.
- **`public_html/citte/podavam_za.php`** — `promo_recalc()` преди copy; промо finalize в imartap swap блок; `discount_applied` в item SELECT/INSERT; negative ред за fixed/shipping; `pordost_coupon_discount`.
- **`public_html/citte/promo-cart-rows.php`** — ред "колко махна ваучерът".
- **SQL миграции** — ALTER колони (всички DB) + DROP промо таблици от per-site (`emart-monorepo/packages/db/scripts/batch-sql-dbs/`).
- **`api/promo-validate-table.sql`** + `mysql-dumps/promo-codes-docs.md` — документираме новите колони + single-source imartap.

## Реюз (вече съществува)
- `cenni()` (`ceni/cenni.php`) — Phase 1, без промяна.
- `PromoCode::validate/getAppliedForCart/markUsed/finalizeForOrder` — реюзваме; `calculateCartDiscount` логиката мигрира в `recalcCart`.
- imartap connection паттерн — `zipchat.php:10`.
- batch SQL tool — `sql-batch-dbs.ts`.

---

## Verification (end-to-end, dev / docker-compose)

1. **Schema:** `SHOW COLUMNS FROM item_l` → `discount_applied`; `SHOW COLUMNS FROM porachki_l` → `pordost_coupon_discount`. Промо таблици само в imartap (`SHOW TABLES` в inmarta → няма promo_codes).
2. **Percent (TEST10/SUMMER20):** добавям артикул → `it_cena`=Phase1; прилагам 10% → `it_cena` пада, `discount_applied = Phase1 − Phase2` (`SELECT it_cena,it_suma,it_osnovna_cena,discount_applied FROM item_l WHERE porach_id=?`). Compare-and-pick-lower: артикул с голяма продуктова отстъпка пази Phase 1.
3. **Идемпотентност:** презареждам количката 2× → стойностите не се менят. Сменям количество → recompute коректен (без double-subtract).
4. **Re-validate:** прилагам код с `min_subtotal`, после махам артикули под прага → кодът отпада автоматично.
5. **Ваучер (FLAT5):** субтоталът намалява с `min(voucher_remainer, subtotal)`; display редът показва сумата; артикулите не са пипнати per ред.
6. **Доставка (FREESHIP):** `cendost` → 0 динамично; `pordost_coupon_discount` записан; махам кода → `cendost` се връща (никаква stored стойност).
7. **Микроинвест:** финализирам ваучер поръчка → `SELECT cat_no,it_cena,it_suma FROM item WHERE porach_id=?` показва negative промо ред; `SUM(it_suma)` = крайна платена сума; репликата в per-site `item` съдържа същия ред.
8. **Регресия без промо:** поръчка без код → `discount_applied=0`, няма negative редове, поведение идентично на сегашното.
9. **Връзки:** добавяме лог преди/след всеки swap (`SELECT DATABASE()`), за да потвърдим: ФАЗА A на регионална → imartap блок на imartap → restore на регионална. След цял cart flow `SHOW PROCESSLIST` да няма натрупани отворени връзки (без leak при `exit` пътищата).

---

## Open items / рискове

- **`$msql_basap` == imartap?** (блокиращо за swap точките) — ако да, в `case.php`/`case_potv.php` промо ops са вече на imartap и swap там отпада; ако не, нужен е навсякъде. Helper-ите работят и в двата случая. Да се сверят и имената на connection globals в `v_case.php` (връзката идва от include, няма явен `mysqli_connect`).
- **Connection leaks:** всеки `emart_db_to_imartap` трябва да има сдвоен `emart_db_restore` по всички пътища, вкл. при early `exit`/грешка (`promo-cart.php` прави `exit` на много места). Да се ползва `try/finally` или явен restore преди всеки `exit`. Никога да не остава отворена imartap връзка след промо блока.
- **Двойни swap-ове в `podavam_za.php`:** новите промо swap-ове се вмъкват сред ~30 съществуващи → внимателно подреждане, за да не се счупи следващ блок, който очаква конкретна база.
- **Праг за free shipping спрямо ваучер:** дали безплатната доставка се определя по pre-promo или post-promo subtotal. Планът приема **pre-promo** (изключва промо редовете от прага) — да потвърдим.
- **Доставка negative ред към Микроинвест:** shipping отстъпката се води в `pordost_coupon_discount` + намален `cendost`. Дали Микроинвест иска и отделен item ред за нея зависи от това как ингестира доставката — да сверим с Иво.
- **Stacking на няколко percent кода:** прилагат се каскадно (всеки върху резултата на предишния); `stack_group` ограничава комбинациите. Да потвърдим желаното поведение при 2+ percent кода.
- **Rounding:** reconstruct на Phase 1 `it_cena` от `it_suma/item_br` може да дрифтне ±0.01; percent се смята от `it_osnovna_cena` (Phase 0), което елиминира дрифт за percent. Тестваме с реални цени.
- **Конкурентност:** ако два таба пишат едновременно в количката, reset-then-apply трябва да е в една заявка/транзакция за да няма race; разглеждаме при имплементацията.

---

## Статус на имплементацията (2026-06-06)

**Готово и проверено:**
- `lib/db-switch.php`, `lib/PromoCalc.php`, `lib/CartItems.php` (нови) + `lib/PromoCode.php` (refactor, imartap-only). Всички lint clean.
- DB миграции приложени на dev (imartap+inmarta): `discount_applied` на item_l/item_no/item; `pordost_coupon_discount` на porachki/porachki_l/porachki_no; промо таблиците създадени в imartap (+ 4 seed кода).
- `api/promo-cart.php`, `api/promo-validate.php` — swap-обвити apply/remove/validate + `promo_recalc`.
- `case.php`, `case_potv.php` — `promo_recalc` преди item read; percent в артикула, ваучер/доставка отделни редове; `pordost_coupon_discount` запис; `promo-cart-rows.php` показва само ваучер при 'discount'.
- `v_case.php` — `discount_applied='0'` при write на item_l/item_no.
- `podavam_za.php` — finalize в imartap swap (voucher+shipping+`finalizeForOrder`), коригиран `porach_suma`/`cendost`/`pordost_coupon_discount`; `discount_applied` в item_l→item copy.
- **Verification:** PromoCalc unit harness (compare-and-pick-lower, ваучер cap, shipping cap, voucher>subtotal) → ALL PASS; всички нови SQL заявки изпълнени срещу реалната схема → валидни.
- **Bug fix:** fixed/ваучер = `min(discount_value, voucher_remainer, subtotal)` (per-use сума, capped от общия бюджет) — оригиналът ползваше само voucher_remainer.

**Отложено (иска staging тест + потвърждение от Иво):**
- **Negative Микроинвест ред за ваучер** в `item`. Сега `porach_suma` се намалява с ваучера, но няма отделен negative item ред → SUM(item.it_suma) (pre-voucher) ≠ porach_suma при ползван ваучер. Percent е коректно в артикулите. Имплементацията на реда взаимодейства с copy-машинарията и free-shipping прага в `podavam_za.php` → отложено до runnable env.

**Не може да се тества локално:** app не е runnable (`zamysql.php` gitignored, `DOCUMENT_ROOT=./www` не сервира `public_html`, host→DB контейнер недостъпим). Render/finalize промените са lint + SQL проверени, но искат staging end-to-end тест.

**Преди production:**
- DROP на промо таблиците от per-site DBs (inmarta/iimarta/almarta…) — единен източник imartap.
- Изтриване на dev seed кодовете (TEST10/SUMMER20/FLAT5/FREESHIP).
- Прилагане на колонните ALTER-и + промо DDL на всички региони през `sql-batch-dbs.ts`.
