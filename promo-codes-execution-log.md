# Promo codes — execution log

> Audit trail на всяка стъпка от изпълнението на `promo-codes-master-plan.md`.
> Append-only. Не редактираме историята — само добавяме нови записи.

Формат на всяка стъпка:

```
## YYYY-MM-DD HH:MM — Step N: <заглавие>
**Какво направено:** ...
**Резултат / output:** ...
**Файлове засегнати:** ...
**Бележки:** ...
```

---

## 2026-05-14 — Step 0: Open questions resolved + pre-flight checks

**Какво направено:**
- Разрешени 4-те отворени въпроса от `promo-codes-master-plan.md` (секция "Отворени въпроси").
- Изпълнени pre-flight SQL queries срещу `imartap` за валидация на source данните.

**Решения:**

| Въпрос | Решение | Основание |
|---|---|---|
| `potrebitel` колоната | **DROP** | 0/18 distinct non-zero стойности match `klienti.klienti_id`. Единственият writer (`promo-codes.php`) не записва тази колона. Никой PHP файл не чете `loyality_points.potrebitel` или `obshti_kodove.potrebitel`. → dead data. |
| `sait` (multi-site) | **KEEP** | Реален сценарий с bg/ro/gr/all стойности — пазим `site` колоната в `promo_codes`. |
| `active` за obshti_kodove | `IF(data_validen > date('YmdHis'), 1, 0)` | Автоматично деактивиране на изтекли при migration. |
| Историческ audit за used loyality_points | **IGNORE** | За `izpolzvan='1'` редовете нямаме `order_id` — губим audit, но без ghost referential integrity. |

**Pre-flight резултати (срещу imartap dev):**

| Check | loyality_points | obshti_kodove |
|---|---|---|
| Total rows | 16,221 | 17 |
| MAX(LENGTH(kod)) | 14 | 12 |
| NULL/bad tip | 0 | **3** (id 7,8,9 — test reds с `kod = 'test7/8/9'`, `tip = NULL`) |
| Empty kod | 0 | 0 |
| Bad date format (не 14-цифров) | 0 | 0 |
| Code collisions с другата таблица | 0 | — |

**Експектация след migration:**
- 16,221 (loyality, всички tip-ове валидни)
- 14 (obshti — 17 минус 3 test-rows с NULL tip, които се филтрират от `WHERE tip IN (0,1,2)`)
- = ~16,235 реда в `promo_codes`

**promo_codes таблица в imartap:** не съществува → fresh CREATE без DROP.

**Файлове засегнати:** няма (само investigation).

**Бележки:**
- `code VARCHAR(50)` лимитът е достатъчен (max 14).
- Investigation на `potrebitel`: provrerih данните и кода — non-zero values в loyality_points (само 86 от 16,221 = 0.5%) идват от legacy/manual writes. PHP grep за `INSERT INTO loyality_points` / `UPDATE loyality_points` намира само 1 writer (`the-marketer/promo-codes.php`), който не пише `potrebitel`. Текущият код не разчита на тази колона.

---

## 2026-05-14 — Step 1: Update master plan with decisions

**Какво направено:**
- Замених секция "Отворени въпроси" в `promo-codes-master-plan.md` с разрешените отговори.
- Update на migration SQL: obshti_kodove `active` колоната използва `IF(data_validen > NOW, 1, 0)` вместо твърдо `1`.

**Файлове засегнати:**
- `promo-codes-master-plan.md`

**Бележки:**
- В migration-а замених PHP-style `date('YmdHis')` с MySQL `DATE_FORMAT(NOW(),'%Y%m%d%H%i%s')` за да работи изцяло в SQL контекст.

---

## 2026-05-14 — Step 2: Update promo-codes-docs.md with new schema

**Какво направено:**
- Презаписах `mysql-dumps/promo-codes-docs.md` с новата схема:
  - `remaining_amount` → `voucher_remainer`
  - Date колони → `VARCHAR(14)` `YYYYMMDDHHmmss`
  - Добавени: `created_at`, `used_at`, `source`, `note`, `site`, `created_by`
  - `cart_promo_codes.created_at` и `order_promo_codes.created_at` като `VARCHAR(14) NOT NULL` (не TIMESTAMP)
- Добавена секция "Стари таблици (deprecated, read-only)" с counts от pre-flight.
- Добавена бележка за string-based date comparison (`strtotime` → директно `<` сравнение).

**Файлове засегнати:**
- `mysql-dumps/promo-codes-docs.md`

---

## 2026-05-14 — Step 4: Execute migration on dev imartap

**Какво направено:**
- Изпълних `/tmp/promo-migration.sql` срещу `lamp-mysql8` контейнера: CREATE TABLE + START TRANSACTION → INSERT IGNORE (loyality) → INSERT IGNORE (obshti) → COMMIT → verification queries.

**Резултат:**

```
== COUNTS ==
loyality_count: 16221
obshti_count:   17
promo_count:    16235
from_marketer:  16221
from_manual:    14    (3 test-rows с NULL tip filter-нати)

== TYPE DISTRIBUTION ==
the-marketer: percent=16144, fixed=76, shipping=1
manual:       percent=12,    fixed=1,  shipping=1

== ACTIVE FLAG ==
the-marketer: active=1 → 16136, active=0 → 85 (изпрозвани историчекси с izpolzvan='1')
manual:       active=1 → 6,     active=0 → 8  (изтекли)

== VOUCHER_REMAINER SANITY ==
percent:  16156 общо / 16156 NULL  (правилно)
fixed:    77 общо    / 0 NULL      (всички populated)
shipping: 2 общо     / 2 NULL      (правилно)
```

**Файлове засегнати:**
- DB `imartap`: създадени `promo_codes`, `cart_promo_codes`, `order_promo_codes`; populated `promo_codes`.
- Старите таблици `loyality_points` и `obshti_kodove` — touch-free.

**Бележки:**
- Sample-вани първите 3 реда the-marketer и 5 реда manual — данните изглеждат коректно мигрирани.
- Транзакцията се commit-на чисто.
- Готово за Step 5: PHP code rewrites.

---

## 2026-05-14 — Step 3: Rewrite DDL file

**Какво направено:**
- Презаписах `public_html/citte/api/promo-validate-table.sql` с новата схема.
- Старата DDL имаше само `promo_codes` + `order_promo_codes`; новата добавя и `cart_promo_codes` (която вече я има в production като TIMESTAMP, но сега е VARCHAR(14)).
- Тестовите INSERT-и обогатени с `created_at`, `source`, `created_by`, `note`. За `FLAT5` (fixed type) — отделен UPDATE за `voucher_remainer`.

**Файлове засегнати:**
- `public_html/citte/api/promo-validate-table.sql`

**Бележки:**
- DDL използва `CREATE TABLE IF NOT EXISTS` — safe за повторно изпълнение.
- Тестовите кодове са seed за dev среда; в production трябва да се изтрият или скриптът да се пропусне.

---

## 2026-05-14 — Step 5: Rewrite the-marketer/promo-codes.php

**Какво направено:**
- INSERT в `loyality_points` → INSERT в `promo_codes`.
- Добавени: type ENUM mapping (PHP), voucher_remainer (за fixed), max_uses=1, active=1, source='the-marketer', created_by='the-marketer'.
- `expiration` сега се quote-ва през `json_encodei()` (за консистентност).
- JSON response непроменен (`code`, `value`, `type`, `expiration`) — The Marketer не вижда промяна.

**Файлове засегнати:**
- `public_html/citte/the-marketer/promo-codes.php`

---

## 2026-05-14 — Step 6: Refactor PromoCode.php

**Какво направено:**
- Глобален rename `remaining_amount` → `voucher_remainer` (SELECT statements, PHP array keys, UPDATE statements).
- `validate()` expiration check: `strtotime($r['expiration_date']) < strtotime('today')` → string compare `$r['expiration_date'] < date('YmdHis')`.
- `markUsed()`: добавен UPDATE на `promo_codes.used_at = date('YmdHis')`; INSERT в order_promo_codes сега включва `created_at`.

**Файлове засегнати:**
- `public_html/citte/lib/PromoCode.php`

**Verification:** `grep "remaining_amount\|strtotime"` → 0 hits. Чисто.

---

## 2026-05-14 — Step 7: Add created_at to cart/order INSERTs

**Какво направено:**
- `public_html/citte/api/promo-cart.php`: INSERT INTO cart_promo_codes сега включва `created_at = date('YmdHis')`.
- `public_html/citte/lib/PromoCode.php::markUsed()`: вече беше fix-нат в Step 6 — INSERT INTO order_promo_codes включва `created_at`.
- `promo-validate.php` — не пипа `cart_promo_codes` или `order_promo_codes`, не се налага промяна.

**Файлове засегнати:**
- `public_html/citte/api/promo-cart.php`

---

## 2026-05-14 — Step 8: Fix consumers of getAppliedForCart()

**Какво направено:**
- Grep `remaining_amount` в `public_html/citte/` (без .sql/.md) → 0 hits.
- Grep `remaining_amount\|voucher_remainer` в `case.php`, `promo-input.php`, `promo-cart-rows.php` → 0 hits.
- UI компонентите не четат тази колона директно — само разчитат на `discount_applied` от cart_promo_codes.

**Файлове засегнати:** няма (no changes needed).

---

## 2026-05-15 — Step 9: Apply new schema to per-site DBs (inmarta, iimarta)

**Какво направено:**
- Runtime error на bg site: `Fatal error: Uncaught mysqli_sql_exception: Unknown column 'pc.voucher_remainer' in 'field list' in PromoCode.php:162`.
- Root cause: master plan мигрира към `imartap.promo_codes`, но cart flow на per-site DB (`zaskiba.php:29 $zuttrttuz="bg"` → `zamysql.php:8 $msql_bgbasa='inmarta'`). `inmarta.promo_codes` все още беше със старата schema (`remaining_amount`, `expiration_date DATE`, без `created_at`/`used_at`/`source`/`note`/`site`/`created_by`); `inmarta.cart_promo_codes.created_at` беше `TIMESTAMP` вместо `VARCHAR(14)`.
- Преди destructive action — проверих row counts в `inmarta`: 10 promo_codes (само dev seed), 1 cart_promo_codes (test ред), 0 order_promo_codes. `iimarta` нямаше нито една от трите таблици.
- Изпълних `DROP TABLE IF EXISTS cart_promo_codes, order_promo_codes, promo_codes` в `inmarta`.
- Изпълних `public_html/citte/api/promo-validate-table.sql` срещу `inmarta` и `iimarta`.

**Резултат:**
- `inmarta.promo_codes` и `iimarta.promo_codes` сега имат новата schema (verified чрез `SHOW COLUMNS` — `voucher_remainer`, `created_at`, `used_at`, `source`, `site` присъстват).
- DDL seed-ва 4 test кода (TEST10, SUMMER20, FLAT5, FREESHIP) в всяка DB.
- Bg cart `PromoCode::getAppliedForCart()` грешката е fix-ната.

**Файлове засегнати:**
- DB `inmarta`: drop+recreate на `promo_codes`, `cart_promo_codes`, `order_promo_codes`.
- DB `iimarta`: fresh create на `promo_codes`, `cart_promo_codes`, `order_promo_codes`.
- Няма промени в репото.

**Бележки:**
- Master plan документира migration **в `imartap`** (където са source данните `loyality_points` + `obshti_kodove`), но real cart-flow таблиците живеят в **per-site DB** (`inmarta`/`iimarta`/`imartap`). Имигрираните 16,235 реда седят в `imartap.promo_codes` и НЕ са достъпни от bg/gr cart.
- Текущо решение (по explicit избор на user): drop+recreate в `inmarta`+`iimarta` **без** data copy от `imartap`. Per-site `promo_codes` остават празни (само seed).
- Ако в бъдеще трябва старите кодове да работят на bg/gr сайтове — нужен е cross-DB copy `imartap.promo_codes` → `inmarta.promo_codes` / `iimarta.promo_codes`, или преосмисляне на архитектурата (single source `imartap.promo_codes` с cross-DB JOIN от per-site cart code).
- Open question за master plan: dataflow inconsistency (source-of-truth DB vs cart DB) трябва да се документира явно.

---
