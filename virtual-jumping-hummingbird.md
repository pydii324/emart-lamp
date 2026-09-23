# Промо кодове — какво трябва да се тества преди deploy

## Context

Issue #610 е функционално готов след пет месеца и осем фази (`public_html/citte/docs/issues/610-promo-codes.bg.md`). Предстои PR `promo_codes` → `main`. Проблемът: **няма как да докажем, че работи.**

Какво намерихме в момента:

- **203 `assert()` в 8 файла** под `public_html/citte/tests/lib/` — покриват само чистите функции на lib слоя. ✅ *Инфраструктурата е оправена — виж Част 2.*
- `inmarta.order_promo_codes` = 0 реда, `imartap.order_promo_codes` = 0 реда. **Нито една завършена поръчка с промо код на тази среда.** Целият redemption път (`PromoCodeCheckout::finalize`, `markUsed`, dual-write, Микроинвест редът) е без реално изпълнение.
- `imartap.promo_codes` има 7 seed кода, всички `site='bg'`. Няма expired, inactive, `min_subtotal`, изчерпан `max_uses`, нито `stack_group` двойка — фикстури за половината validation пътища липсват.
- Локално има само `inmarta` (bg) + `imartap` (`citte/zamysql.php:27,33`). Друг регион не може да се тества тук.

Резултат: чеклист какво да минем през фронтенда + попълване на дупките в автоматичното покритие + два кода фикса.

**Решения от разговора:** blocker за deploy е само имейл бъгът; `shipping_percent` пада изцяло от кода; регионите се тестват bg-only локално, останалото на staging.

---

## Част 1 — Чеклистът: какво трябва да се мине през фронтенда

Всичко долу е bg/EUR на `https://localhost:8453/`. Маркираните **[staging]** не могат да се изпълнят локално.

### 1.1 Валидация — съобщения в `#promo-msg`

Източник на низовете: `citte/lib/PromoCodeCatalog.php:44-70,169-174`, `citte/api/promo-cart.php:15-236`.

| # | Вход | Очаквано |
|---|---|---|
| 1 | празно поле | `Въведи промо код` |
| 2 | несъществуващ код | `Невалиден код` |
| 3 | код на друг регион | `Невалиден код` — **умишлено същото**, за да не се изброяват чужди кодове (`PromoCodeCatalog.php:204-208`) |
| 4 | `active = 0` | `Кодът не е активен` |
| 5 | `expiration_date` в миналото | `Кодът е изтекъл` |
| 6 | количка под `min_subtotal` | `Минимална сума за код: N.NN EUR` — **валутата на региона, не „лв."** |
| 7 | `times_used >= max_uses` | `Кодът е изчерпан` |
| 8 | същият код втори път | `Кодът вече е приложен` |
| 9 | втори код от същия `stack_group` | `Не може да се комбинира с вече приложен код от същата група` |
| 10 | код при празна количка | `Количката е празна` |
| 11 | POST без `X-Requested-With` | 403 `Невалидна заявка` (`promo-session.php:57-81`) |
| 12 | подменен `mart_bg` cookie към чужда количка | 403 `Невалидна сесия` |

Редът в 4→5→6→8 е контракт — `rejectionReason()` е `match(true)` отгоре надолу (`PromoCodeCatalog.php:168-176`).

### 1.2 Типове и сметки в количката (`/moiata-koshnica`)

| # | Сценарий | Очаквано |
|---|---|---|
| 13 | `percent` | задраскана стара цена до артикула, **без отделен ред** (`PriceDisplay::oldUnit()`, `case.php:340-351`) |
| 14 | два `percent` (10% и 20%) | прилага се само 20-те; 10-те **остават** в количката с 0 (`PromoCalc.php:62-69`) |
| 15 | `fixed` / `voucher` | отрицателен ред SKU `5555555` |
| 16 | `fixed` / `coupon` | отрицателен ред SKU `7777777` |
| 17 | ваучер > количката | капва се на количката, изгаря се цял, **без остатък** |
| 18 | преливане на ваучера | остатъкът пада върху доставката, но не под 0 |
| 19 | `shipping`, `shipping_cap = NULL` | доставката пада на 0 |
| 20 | `shipping`, `shipping_cap = 3.00` | доставката пада с най-много 3.00 |
| 21 | `shipping_cap = 0.00` vs `NULL` | **не са едно и също** — 0.00 не сваля нищо |
| 22 | `fixed` + `shipping` заедно | стакват се |

### 1.3 Живот на кода между заявките

Кодовете живеят в `cart_promo_codes`, ключ `(cart_id, cart_type)` — не в сесия, не в cookie.

| # | Сценарий | Очаквано |
|---|---|---|
| 23 | кошче на промо реда в таблицата | маха **кода**, не реда (`mahni_ot_case.php:41-61`) |
| 24 | ✕ на чипа | същото, през `removePromoCode()` |
| 25 | смяна на количество след прилагане | кодът оцелява, сумата се преизчислява |
| 26 | гост слага код → логва се | `promo_migrate_cart()` мести от `cart_type='no'` към `'l'` (`index.php:676`) |
| 27 | mini-cart в header-а | нетна сума (`header.php:341,344`) |

### 1.4 Стъпка 2 — доставка и плащане

| # | Сценарий | Очаквано |
|---|---|---|
| 28 | shipping код + списък куриери | цените на куриерите са **вече нетни** (`case_dopl.php:383-420`) |
| 29 | смяна на куриер | отстъпката се преизчислява за новата цена, старата не изтича |
| 30 | след стъпка 2 | `porachki_*.cendost_baza` е записана |

### 1.5 Стъпка 3 — потвърждение

| # | Сценарий | Очаквано |
|---|---|---|
| 31 | сметката | subtotal нетен, доставка със задраскано бруто, крайна сума вярна |
| 32 | код, паднал между стъпка 1 и 3 | **днес не се показва нищо** — банерът е само в `case.php:233-250`. Известен gap, не blocker |
| 33 | PayPal | `discount_amount_cart` положителен, никакъв отрицателен `amount_N` |

### 1.6 Финализиране — тук е най-голямата дупка

Нито един от тези никога не е изпълняван на тази среда.

| # | Проверка | Как |
|---|---|---|
| 34 | ред в `order_promo_codes` и в **двете** бази | SQL |
| 35 | `cart_promo_codes` изчистена за тази количка | SQL |
| 36 | `promo_codes.times_used` +1 | SQL |
| 37 | `cendost = MAX(0, cendost_baza − pordost_coupon_discount)` | SQL, инвариантът от `fresh/04` |
| 38 | `porachki.porach_suma` нетна | SQL |
| 39 | `item` редовете носят `discount_applied`, `it_cena_new`, `it_suma_new` | SQL |
| 40 | отрицателният Микроинвест ред е и в двете бази | SQL |
| 41 | `markUsed()` при `max_uses = 1`, две паралелни заявки | само едната минава — гардът е в WHERE-а, не в PHP (`PromoCodeCatalog.php:136-140`) |

### 1.7 След поръчката

| # | Сценарий | Очаквано |
|---|---|---|
| 42 | `/potvardih-porachkata` | приложените кодове се виждат |
| 43 | `moiteporachkipregled.php` | задраскана цена на артикула и на доставката |
| 44 | **имейлът, percent код** | **Днес е грешен — виж Част 3.1** |

### 1.8 Провал

| # | Сценарий | Очаквано |
|---|---|---|
| 45 | imartap пада по време на финализиране | връзката се възстановява, **количката НЕ се изчиства**, няма записани id-та |
| 46 | `$zuttrttuz` с непознат регион | кодовете са изключени, сайтът не гърми (`PromoRegion::sqlCondition()` връща литерал `NULL`) |
| 47 | **[staging]** ro/RON и al/ALL количка | съобщението за мин. сума е в правилната валута |
| 48 | **[staging]** код на bg, въведен на ro | `Невалиден код` |

---

## Част 2 — Тестовата инфраструктура ✅ ГОТОВО (20.09.2026)

Всички тестове са под `citte/tests/`, разделени по **рънър**, защото трите вида
не се пускат от една програма:

```
public_html/citte/tests/
  .htaccess          Require all denied — citte/ се сервира по HTTP
  run-asserts.sh     обхожда lib/*Test.php, всеки в собствен процес
  phpunit/           PHPUnit класове — САМО това сканира phpunit.xml
  lib/               8 голи assert() скрипта (огледало на citte/lib/)
  pest/              Pest, не е инсталиран и е недовършен — извън scope
```

Какво се направи:

1. **`citte/tests/auth/` → `citte/tests/phpunit/`**, `public_html/tests/citte/{lib,utils}/` → `citte/tests/lib/`. `PayPalCartTest.php` мина от `utils/` в `lib/` — тества `citte/lib/PayPalCart.php`. `require_once` пътищата и самореферентните коментари са поправени.
2. **`phpunit.xml`** сочи само `citte/tests/phpunit`. Pest файлът вече не чупи run-а — без `<exclude>` списък, който да гние.
3. **`citte/tests/run-asserts.sh`** — всеки assert скрипт в собствен php процес с `-d zend.assertions=1`, защото стубовете на `dbq()` се сблъскват. Проверено, че хваща провал: нарочно счупен assert дава `FAIL` + exit 1.
4. **`composer test`** = `test:phpunit` + `test:asserts`.
5. **`citte/tests/.htaccess`** с `Require all denied`. `public_html/citte/` няма свой `.htaccess`, а front controller-ът не пренаписва съществуващи файлове (`RewriteCond %{REQUEST_FILENAME} !-f`) — без това тестовете се **изпълняват** по HTTP. Проверено: 403.
6. **`citte/docs/running-tests.md`** пренаписан.

Текущо състояние: `composer test` → PHPUnit 31/31 OK, 8/8 assert скрипта OK.

---

## Част 3 — Кода фикса

### 3.1 [BLOCKER] Percent отстъпката липсва в имейла

`citte/podavam_za.php:1246-1248` чете `it_cena, it_suma` — **брутните** колони. Откакто percent кодовете нямат отрицателен ред (2026-09-05), отстъпката не се появява никъде в имейла, а `porachki.porach_suma` (`:369`) е нетна. Клиентът получава имейл, чиито числа не се връзват с платеното.

Данните вече са там: INSERT-ът на `:168` копира `discount_applied`, `it_cena_new`, `it_suma_new` от `item_l` в `item`.

Фиксът е в SELECT-а — вземи нетните с fallback, без да пипаш цикъла на рендера:

```sql
SELECT item_id, cat_no, item_br,
       COALESCE(NULLIF(it_cena_new, 0), it_cena) AS it_cena,
       COALESCE(NULLIF(it_suma_new, 0), it_suma) AS it_suma,
       ...
```

Двата branch-а (`:1246` за логнат, и guest огледалото) трябва да минат еднакво — провери дали guest пътят ползва същата заявка.

Доставката вече е вярна (`:1598-1605`) — не я пипай.

### 3.2 `shipping_percent` пада изцяло

Типът е махнат от DB ENUM-а на 21.08, но PHP още го носи. Махни го отвсякъде:

| Файл | Какво |
|---|---|
| `citte/lib/PromoCalc.php:122,125,144,155,192,209` | branch-а в `shipDiscountForRow()` + двата `in_array` филтъра |
| `citte/lib/PromoCodeCatalog.php:189,197` | arm-а в `previewDiscount()` |
| `citte/promo-cart-rows.php:21` | `in_array` |
| `citte/promo-input.php:57` | `in_array` |
| `citte/lib/db-switch.php:71,79` | само коментари |
| `citte/tests/lib/PromoCodeCatalogTest.php:131-132` | assert-ът за `previewDiscount('shipping_percent', ...)` |
| `emart-monorepo/packages/db/src/{imartap,domainsMain}/schema.ts` | `mysqlEnum` още изброява `"shipping_percent"` |

**Внимание — не просто махай ключ 3.** `citte/the-marketer/promo-codes.php:66-67`:

```php
$typeMap = [0 => 'fixed', 1 => 'percent', 2 => 'shipping', 3 => 'shipping_percent'];
$typeStr = $typeMap[(int)$type] ?? 'percent';
```

Ако махнеш само `3 => ...`, `type=3` **тихо става `percent`** и `value=50` се записва като 50% отстъпка. Върни 400 при непознат тип:

```php
$typeMap = [0 => 'fixed', 1 => 'percent', 2 => 'shipping'];
if (!isset($typeMap[(int)$type])) {
    http_response_code(400);
    echo json_encodei(['status' => 'error', 'error' => 'Невалиден тип промо код']);
    return;
}
```

Плюс dev базата: `ALTER` на `imartap.promo_codes.type` и `inmarta.cart_promo_codes.type` да махне стойността, след изтриване на seed ред `id=6` (`SHIPPCT50`). Файл в `database/migrations/deploy/`, по конвенцията на директорията (без `IF EXISTS` гардове).

Докладвай в `610-promo-codes.bg.md` и `.en.md` — редът в „Преди deploy" се затваря.

---

## Част 4 — Липсващите тестове

Пиши ги в стила на съществуващите: гол `assert()` скрипт, `php -d zend.assertions=1`, `echo "OK\n"` накрая. Никакъв framework, никакви фикстури.

**Чисти функции без DB (нови файлове в `citte/tests/`):**

| Файл | Какво покрива |
|---|---|
| `citte/tests/lib/PriceDisplayTest.php` | `oldUnit()` / `cell()` — задрасква само когато има реална отстъпка, не при равни цени |
| `citte/tests/lib/CartItemsTest.php` | `subtotal()`, `applyItemDiscounts()` — стуб-ни `dbq` както другите |
| `citte/tests/lib/DbSwitchPromoTest.php` | `promo_sku_for()` (само `fixed` връща SKU), `promo_cart_skus()`, `promo_row_code_map()`, и че `promo_sync_cart_rows()` хвърля при разминаване на `$plan`/`$rows` (`db-switch.php:171-177`) |

**Регресии за двата фикса (задължителни, иначе фиксовете нямат гард):**

| Файл | Какво |
|---|---|
| `citte/tests/lib/PromoCalcTest.php` | **изтрий** асертите за `shipping_percent`; добави: ред с `type='shipping_percent'` се игнорира от `compute()` и `shippingPlan()` |
| `citte/tests/lib/TypeMapTest.php` | непознат `type` НЕ става `percent`. Изнеси картата в чиста функция, за да е тестваема без HTTP |

**Нови фикстури в `database/migrations/fresh/08-seed-imartap-promo_codes.sql`** — без тях половината от Част 1.1 не може да се мине:

```
EXPIRED      percent  expiration_date в миналото
INACTIVE     percent  active = 0
MIN50        percent  min_subtotal = 50.00
ONESHOT      fixed    max_uses = 1
STACK1A/1B   percent  stack_group = 1
```

Плюс изтриване на `SHIPPCT50` (id 6) и оправяне на `VOUCHER500ALL` (id 7) — `site='bg'` с `currency='ALL'` нарушава инварианта „един регион = една валута".

---

## Verification

Поред, всяка стъпка е gate за следващата:

1. **Unit:** `cd public_html && composer test` → всичките 8+3 файла минават, `phpunit` минава без fatal.
2. **Миграции:** пусни новия `deploy/` файл и seed-а; `SHOW COLUMNS FROM imartap.promo_codes LIKE 'type'` не показва `shipping_percent`; `SELECT code FROM imartap.promo_codes` показва новите фикстури.
3. **E2E, ръчно през браузъра** (`https://localhost:8453/`, Playwright MCP или на ръка) — Част 1, точки 1–46. Точки 47–48 се маркират като staging.
4. **Финализиране** — мини цяла поръчка с percent + voucher + shipping код и провери:
   ```sql
   SELECT porach_suma, cendost, cendost_baza, pordost_coupon_discount FROM inmarta.porachki WHERE porachki_id = ?;
   SELECT * FROM inmarta.order_promo_codes WHERE order_id = ?;
   SELECT * FROM imartap.order_promo_codes WHERE order_id = ?;
   SELECT COUNT(*) FROM inmarta.cart_promo_codes WHERE cart_id = ?;  -- 0
   SELECT code, times_used FROM imartap.promo_codes WHERE code IN (...);
   SELECT cat_no, it_cena, it_suma, it_cena_new, it_suma_new, discount_applied FROM inmarta.item WHERE porach_id = ?;
   ```
5. **Имейлът** — вземи същата поръчка и виж, че артикулните цени и subtotal-ът в имейла съвпадат с `porachki.porach_suma`. Това е фикс 3.1 и е blocker-ът.
6. **SQLi харнесът** — `test-sqli.php` минава (покрива динамичните `IN (…)`, multi-row VALUES, race гарда на `markUsed()`).

---

## Резултати от пускането — 20.09.2026, bg/EUR, количка 6.00 → 10.00

Пуснато през реалния HTTP стек (`https://localhost:8453/`), не през стубове.

### 1.1 Валидация — **12/12 минават**

Всички съобщения съвпадат дума по дума. Редът `active` → `expired` → `min_subtotal`
→ `вече приложен` е доказан: `QAINACTIVE` е И неактивен, И изтекъл, и връща
„Кодът не е активен". `QARO` и `QANOSUCH` дават идентичен отговор — региона не
изтича. CSRF: липсващ `X-Requested-With` → 403, чужд `Origin` → 403, подменен
`mart_bg` към чужда количка → 403 „Невалидна сесия".

### 1.2 Типове и сметки — **10/10 минават**

| # | Резултат |
|---|---|
| 13 | `<s>2.00</s>` → `1.80`, `<s>6.00</s>` → `5.40`. Нула промо SKU в HTML-а |
| 14 | `QAPCT20` applied=1.20, `QAPCT10` applied=**0.00** и остава в количката |
| 15 | SKU `5555555`, `it_cena=-5`, `it_suma=-5` |
| 16 | SKU `7777777`, същото |
| 17 | 500.00 ваучер → applied=**6.00** (капнат на количката), изгаря цял |
| 18 | Остатъкът прелива: „Промо код QAVOUCHERBIG (доставка): −5.88 лв.", общо 0.00 |
| 19 | cap NULL → 6.00 + 5.50 − 5.50 = **6.00** |
| 20 | cap 3.00 → 6.00 + 5.50 − 3.00 = **8.50** |
| 21 | cap 0.00 → 6.00 + 5.50 − 0 = **11.50**. NULL ≠ 0.00 оцелява през целия път |
| 22 | Трите типа заедно: percent 1.20, после ваучер 4.80 (**не** 5.00 — percent вече е взел своето), после доставка. Редът percent → fixed → shipping се спазва |

### 1.3 Живот на кода — **4/5**, едно блокирано

| # | Резултат |
|---|---|
| 23 | Кошчето на промо реда е `onclick="removePromoCode(65)"` — маха кода, не реда ✅ |
| 24 | `action=remove` трие и кода, и отрицателния `item_no` ред ✅ |
| 25 | Количество 3 → 5: кодът оцелява, applied 1.20 → **2.00** преизчислено ✅ |
| 26 | **Блокирано** — логването минава през Google reCAPTCHA (`vlizali.php:35`). Иска човек в браузър |
| 27 | Mini-cart: „Общо 2 продукта **5.00 лв.**" = 10.00 − 5.00, нетно ✅ |

За #26: акаунтът `ikurkchiev@abv.bg` вече има работеща парола `QaTest123!`
(колоната държеше плейнтекст `123456`, който `parola_verify()` така или иначе
отхвърля). `grupa_otstapki = 0`, значи не е wholesale и промо кодовете важат.
Провери преди и след логване:

```sql
SELECT cart_id, cart_type, code FROM inmarta.cart_promo_codes;
-- преди: cart_type='no', cart_id = sesii_id
-- след:  cart_type='l',  cart_id = porachki_l.porachki_id
```

### Три находки, нито една blocker

1. **Таванираният shipping код се казва „Безплатна доставка".** `QASHIPCAP3` сваля
   3.00 от 5.50 и реда пише „Безплатна доставка (QASHIPCAP3): −3.00 лв." Доставката
   не е безплатна. Етикетът идва от fallback-а в `promo-cart-rows.php` — редове
   3106/3107 липсват в `promenliviprevodi`. Влиза при „Преводи" в чеклиста.
2. **Промо редът линква към `/p/`.** `onclick="location.href='…/p/'"` — промо SKU-то
   няма продуктова страница. Редът трябва да е без линк.
3. **Ваучер, който зануляла количката, удря минимума за поръчка.** При subtotal 0.00
   излиза „Минимална сума за поръчка 5 лв." Взаимодействие за Иво, не бъг в кода.

### Какво остава непуснато

1.4 (стъпка 2), 1.5 (стъпка 3), 1.6 (финализиране), 1.7 (имейл и история),
1.8 #45/#46. Плюс #26 и staging-овите #47/#48.

---

## Резултати от пускането — част 2 (20.09.2026), гост количка, bg/EUR

Поръчки 421629–421634 минаха през реалния HTTP стек. `mail()` е прихванат с
шим на `/usr/sbin/sendmail` в `lamp-php84`, който записва писмата в
`/tmp/qa-mail/` — нищо не е изпратено навън.

**Преди това се приложи липсваща миграция:** `database/migrations/deploy/13-add-cendost-baza.sql`
не беше пусната на dev. `cendost_baza` липсваше и в трите таблици на `inmarta`
и в `imartap.porachki`. Без нея 1.5/1.6 изобщо не могат да се минат.

### 1.4 Стъпка 2 — **3/3**

| # | Резултат |
|---|---|
| 28 | 5.50 → **2.50** с `QASHIPCAP3`; с `QAFREESHIP` отгоре цената изчезва (0.00) ✅ |
| 29 | Всеки вариант (до адрес / до офис) смята на **копие** на `$_promoRows` — и двата получиха 2.50, отстъпката не се изяжда от първия ✅. Различни цени по куриер не са тестваеми локално: само `Спиди` има цена, `ДРУГО` е фиксирано 0 |
| 30 | `porachki_no.cendost_baza = 5.50`, `pordost_coupon_discount = 3.00` ✅ — но се пише на **стъпка 3** (`case_potv.php:850`), не на стъпка 2. Чеклистът беше неточен |

### 1.5 Стъпка 3 — **3/3**

| # | Резултат |
|---|---|
| 31 | „Стойност: 13.00", доставка 5.50, отделен ред −3.00, „Общо: 15.50" ✅. 6 задраскани цени по артикулите. Доставката **не** е задраскана — рендира се бруто + отрицателен ред. Различно от описанието в чеклиста, аритметично вярно |
| 32 | Потвърден gap: деактивиран код тихо изчезва от `cart_promo_codes`, сметката се преизчислява вярно (17.50), **нищо не се казва на клиента** |
| 33 | PayPal: `amount_N` = 1.80 (нетно), нула отрицателни редове, `discount_amount_cart = 5.00`, `shipping_N` сумира 2.50 ✅ |

### 1.6 Финализиране — **8/8 след три фикса**

| # | Резултат |
|---|---|
| 34 | Идентични редове в `inmarta.order_promo_codes` и `imartap.order_promo_codes` ✅ |
| 35 | `cart_promo_codes` = 0 реда ✅ |
| 36 | `times_used` +1 за всеки код ✅ |
| 37 | `cendost = MAX(0, 5.50 − 3.00) = 2.50` ✅ |
| 38 | `porach_suma = 11.00` при бруто 20.00, 20% и ваучер 5.00 ✅ |
| 39 | `discount_applied`, `it_cena_new`, `it_suma_new` пренесени ✅ |
| 40 | Отрицателните редове 5555555 / 7777777 са в **двете** бази ✅ — **след фикс, виж по-долу** |
| 41 | `QAONESHOT` втори път → „Кодът е изчерпан" ✅ |

### 1.7 След поръчката

| # | Резултат |
|---|---|
| 42 | **Блокирано локално.** `podavam_za.php:1877` пише `setcookie("mart_podzav1", …)`, но `the-marketer/utils/v2/set-email.php:42` вече е ехнал `<script>` → `Cannot modify header information`. С `output_buffering = 0` (случаят тук) бисквитката не се слага и `/potvardih-porachkata` е празна. На production зависи от `php.ini`. **Не е промо бъг**, но трябва да се провери на staging |
| 43 | Блокирано — иска логване (reCAPTCHA) |
| 44 | **Беше blocker, фикснат и проверен** — виж по-долу |

### 1.8

| # | Резултат |
|---|---|
| 45 | Не е пускано — иска контролирано падане на imartap |
| 46 | Покрито от `PromoRegionTest.php:57` (`sqlCondition()` → литерален `NULL`) ✅ |

---

## Три бъга, намерени при пускането

### 1. `ot_adm` чупеше всеки отрицателен Микроинвест ред — [BLOCKER, фикснат]

`promo_micro_voucher_row()` изброяваше `ot_adm` и ѝ подаваше `''`. Колоната е
`INT NOT NULL DEFAULT 1`, а `sql_mode` съдържа `STRICT_TRANS_TABLES` (стандартът
на MySQL 8) → `ERROR 1366`. INSERT-ът се проваляше и в двете бази, а грешката
само се логваше:

```
promo_micro_voucher_row: INSERT into item failed for order 421629 (5555555, -5.00):
```

Тоест **никога** не е работил. Отстъпката от ваучер/купон не стигаше до поръчката
като позиция: `porach_suma` беше 13.00, а сборът на артикулните редове 18.00.
Складът обработва поръчката на пълна стойност.

Фикс: колоната пада от списъка и остава на DEFAULT-а — точно както прави
`promo_sync_cart_rows()`. Guard: `citte/tests/lib/DbSwitchPromoSqlTest.php`.

### 2. `markUsed()` обявяваше всеки код за изчерпан — [фикснат]

`dbqp()` → `db_exec()` пуска `$stmt` при връщане; деструкторът нулира брояча на
връзката, така че `mysqli_affected_rows($this->db)` след това връща **−1**.
`-1 < 1` → всяка поръчка логваше всичките си кодове като `exhausted_promo_ids`.
Докблокът над функцията предупреждаваше точно за това.

Гардът в `WHERE`-а си работеше (кодовете не се преразходват), но върнатата
стойност не значеше нищо и `promo.log` се пълнеше с фалшиви тревоги — истинско
изчерпване не се различава от шума.

Фикс: `markUsed()` не минава през `dbqp()`; чете `mysqli_stmt_affected_rows($stmt)`
докато statement-ът е жив.

### 3. Фалшиво „Артикулът е с ограничена наличност" — [фикснат]

Промо редът влизаше с `total = 0` и `item_br = 1`. Проверката
`total < item_br` (`case.php:90`, `case_potv.php:333`, `podavam_za.php:1284`)
палеше предупреждението за изчерпана стока в количката, на стъпка 3 **и в
имейла** — при всяка поръчка с ваучер или купон.

Фикс: `total = 1` и в двата inserter-а (`promo_micro_voucher_row()` и
`promo_sync_cart_rows()`, където колоната изобщо липсваше и падаше на DEFAULT 0).

---

## Част 3.1 — имейлът: фикснат и проверен

`podavam_za.php:1246` четеше `it_cena` / `it_suma`. Прихванатият имейл за
поръчка 421632 (бруто 20.00, `QAPCT20`, ваучер 5.00, `QASHIPCAP3`):

```
Ед. цена 2.00   Количество 5   Общо 10.00 лв.      ← бруто
Обща стойност: 15.00 лв.                            ← porach_suma е 11.00
Общо за поръчката: 17.50 лв.                        ← реално се дължи 13.50
```

Клиентът получаваше сметка с **4.00 лв. повече** от записаното в базата.

След фикса (`COALESCE(NULLIF(it_cena_new,0), it_cena)`), поръчка 421633:

```
Ед. цена 1.60   Количество 5   Общо 8.00 лв.
Обща стойност: 11.00 лв.        = porachki.porach_suma
Цена на доставка: 5.50 2.50 лв.
Общо за поръчката: 13.50 лв.    = 11.00 + 2.50
```

Заявката е една и обслужва и двата клона (логнат и гост) — няма огледало за
оправяне.

---

## Част 3.2 и Част 4 — затворени (21.09.2026)

### 3.2 `shipping_percent`

Падна отвсякъде. PHP-то — в commit `8f616ff`; остатъкът мина сега:

- `emart-monorepo/packages/db/src/{imartap,domainsMain}/schema.ts` — `mysqlEnum`
  вече не изброява типа, тоест Drizzle схемата отговаря на ENUM-а след
  `database/migrations/deploy/16` + `17`.
- Редът в „Преди deploy" на `610-promo-codes.bg.md` / `.en.md` е затворен.
- Картата на The Marketer вече не е инлайн: `PromoCodeCatalog::typeFromTheMarketer()`
  връща `null` за непознат тип, а `citte/the-marketer/promo-codes.php` вдига 400.
  Гардът е в `PromoCodeCatalogTest.php` (секция 9) — проверено с нарочна мутация
  `default => 'percent'`: асертът пада.

### Част 4 — тестовете

Три нови assert скрипта, всичките в стила на съществуващите:

| Файл | Какво |
|---|---|
| `citte/tests/lib/PriceDisplayTest.php` | `net()`, `oldUnit()`, `cell()`, `amount()` — задраскване има само при реална отстъпка (прагът е стотинка), промо редът няма каталожна база |
| `citte/tests/lib/CartItemsTest.php` | `subtotal()`, `read()`, `applyItemDiscounts()` със стубнат `dbq` — липсващ ключ в плана ВРЪЩА реда на Фаза 1. Проверено с мутация: `continue` вместо нулиране чупи теста |
| `citte/tests/lib/DbSwitchPromoTest.php` | `promo_sku_for()`, `promo_cart_skus()`, `promo_cart_row_ime()`; пази и огледалото `CartItems::PROMO_SKUS` да не се разминава |

`TypeMapTest.php` не е отделен файл — картата живее в `PromoCodeCatalog`, така че
асертите ѝ са там, където са и другите решения по тип.

`promo_sync_cart_rows()` не може да се тества без база (DELETE-ът е преди гарда),
затова четирите ѝ случая са в `test-sqli-promo.php`: хвърля при разминат план,
пише точно един отрицателен ред с `total = 1`, идемпотентна е, и не пише нищо при
нулева отстъпка.

Текущо: `composer test` → **PHPUnit 31/31, 12/12 assert скрипта**.

### Verification стъпка 6 — SQLi харнесът

`https://localhost:8453/test-sqli.php?t=runsqli9271` → **60 passed, 0 failed**.
Дотук не беше пускан след промо промените и се оказа, че спира по средата:

1. `new_select()` / `new_delete()` чакаха `mysqli_sql_exception`, но `dbq()` вика
   `showerror1()`, който прави `exit` — целият run умираше на пети случай. Сега
   тези случаи минават през `db_exec()` с no-op handler.
2. Трите случая за `max_uses` четяха `mysqli_affected_rows($connection)` след
   `dbq()`, тоест −1 — точно бъгът, който `markUsed()` вече избягва. Пренаписани
   да четат от живото statement, плюс нов случай, който фиксира самия капан.
3. Случаят за `shipping_cap` приемаше, че `''` влиза като 0.00 — при
   `STRICT_TRANS_TABLES` редът се отказва изцяло. Асертът вече покрива и двете.

### Фикстурите

`fresh/08` вече seed-ва `VOUCHER500ALL` като `site='al'` — инвариантът „един
регион = една валута" е спазен, а коментарът за конверсия през `currency_rates`
(махната на 10.09) е махнат. QA seed-ът трие само стария `site='bg'` вариант.

## Остава

- #26, #42, #43 — искат браузър и логване (reCAPTCHA, `output_buffering`).
- #45 — иска контролирано падане на imartap.
- #47/#48 — staging.
- Трите находки от 20.09: липсващите преводи 3106/3107 („Безплатна доставка" при
  таваниран код), линкът `/p/` на промо реда, и минимумът за поръчка при ваучер,
  който зануляла количката.
