# Промо кодове — консолидация и миграция

Консолидация на `loyality_points` + `obshti_kodove` + старата `promo_codes` в единна `promo_codes` таблица с pivot tables `cart_promo_codes` и `order_promo_codes`. Date колоните преминават от `DATE`/`TIMESTAMP` към `VARCHAR(14)` в `YYYYMMDDHHmmss` формат за консистентност с установената конвенция в `imartap`.

## Резултат накратко

| Метрика | Стойност |
|---|---|
| Мигрирани редове в `imartap.promo_codes` | **16,235** (16,221 the-marketer + 14 manual) |
| Refactor-нати PHP файлове | 4 (`PromoCode.php`, `promo-codes.php`, `promo-cart.php`, `promo-validate.php`) |
| Нови таблици | `promo_codes` (нова schema), `cart_promo_codes`, `order_promo_codes` |
| Premахнати функционалности | `max_uses_per_user` (по решение на колегата) |
| Добавени функционалности | `times_used` брояч (вместо COUNT върху `order_promo_codes`) |
| Засегнати DB | `imartap`, `inmarta`, `iimarta` |

---

## Целева схема

<details>
<summary><b>📋 promo_codes (главна таблица)</b></summary>

```sql
CREATE TABLE `promo_codes` (
  `id`                INT          NOT NULL AUTO_INCREMENT,
  `code`              VARCHAR(50)  NOT NULL,
  `type`              ENUM('percent','fixed','shipping') NOT NULL DEFAULT 'percent',

  -- Стойност
  `discount_value`    DECIMAL(10,2) NOT NULL,
  `voucher_remainer`  DECIMAL(10,2) NULL DEFAULT NULL,

  -- Ограничения
  `min_subtotal`      DECIMAL(10,2) NOT NULL DEFAULT 0,
  `shipping_cap`      DECIMAL(10,2) NULL DEFAULT NULL,
  `max_uses`          INT          NOT NULL DEFAULT 0,
  `times_used`        INT          NOT NULL DEFAULT 0,

  -- Поведение
  `active`            BOOLEAN      NOT NULL DEFAULT TRUE,
  `stack_group`       TINYINT      NULL DEFAULT NULL,

  -- Дати (VARCHAR(14) YYYYMMDDHHmmss)
  `expiration_date`   VARCHAR(14)  NULL DEFAULT NULL,
  `created_at`        VARCHAR(14)  NOT NULL,
  `used_at`           VARCHAR(14)  NULL DEFAULT NULL,

  -- Произход / metadata
  `source`            ENUM('the-marketer','manual','bulk-import') NOT NULL DEFAULT 'manual',
  `note`              VARCHAR(255) NULL DEFAULT NULL,
  `site`              VARCHAR(10)  NULL DEFAULT NULL,
  `created_by`        VARCHAR(255) NULL DEFAULT NULL,

  PRIMARY KEY (`id`),
  UNIQUE KEY `code` (`code`),
  KEY `idx_active_exp` (`active`, `expiration_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| Колона | Описание |
|---|---|
| `type` | `percent`/`fixed`/`shipping` |
| `discount_value` | Стойност на отстъпката |
| `voucher_remainer` | Само за `fixed` — наличен бюджет (бивш `remaining_amount`) |
| `max_uses` | Брой общи употреби; `0` = безлимит; `1` = single-use |
| `times_used` | Брояч на употреби; `++` при `markUsed()` |
| `stack_group` | `NULL` = комбинира се с всичко; число = ексклузивна група |
| `source` | `'the-marketer'` / `'manual'` / `'bulk-import'` |
| `site` | Site scope `'bg'`/`'ro'`/`'gr'`/`'all'` (бивш `sait`) |

</details>

<details>
<summary><b>📋 cart_promo_codes (приложени в активна количка)</b></summary>

```sql
CREATE TABLE `cart_promo_codes` (
  `id`               INT          NOT NULL AUTO_INCREMENT,
  `cart_id`          INT          NOT NULL,
  `cart_type`        ENUM('l','no') NOT NULL,
  `promo_code_id`    INT          NOT NULL,
  `code`             VARCHAR(50)  NOT NULL,
  `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `type`             ENUM('percent','fixed','shipping') NOT NULL,
  `shipping_cap`     DECIMAL(10,2) NULL DEFAULT NULL,
  `created_at`       VARCHAR(14)  NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_cart_promo` (`cart_id`,`cart_type`,`promo_code_id`),
  CONSTRAINT `fk_cpc_promo` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

`cart_type`: `'l'` = логнат потребител (`porachki_l`); `'no'` = гост (`porachki_no`)

</details>

<details>
<summary><b>📋 order_promo_codes (финализирани употреби)</b></summary>

```sql
CREATE TABLE `order_promo_codes` (
  `id`               INT          NOT NULL AUTO_INCREMENT,
  `order_id`         INT          NOT NULL,
  `promo_code_id`    INT          NOT NULL,
  `klienti_id`       INT          NOT NULL DEFAULT 0,
  `discount_applied` DECIMAL(10,2) NOT NULL,
  `created_at`       VARCHAR(14)  NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_order_promo` (`order_id`,`promo_code_id`),
  CONSTRAINT `fk_opc_promo` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

Insert-ва се от `PromoCode::markUsed()`. Глобалният брояч `promo_codes.times_used` се incrementерва паралелно (`UPDATE promo_codes SET times_used = times_used + 1 WHERE id = ?`).

</details>

---

## Логика на изчисление

<details>
<summary><b>🧮 percent тип — per-item compare-and-pick-lower</b></summary>

За всеки артикул се сравняват две цени, използва се по-ниската:

```
promoPrice_i = osnovna_cena_i × qty_i × (1 - promo% / 100)
effective_i  = min(it_suma_i, promoPrice_i)
discount_i   = it_suma_i - effective_i
```

| Артикул | `it_suma` (намалена) | `osnovna × qty` (каталожна) | При 40% промо | Резултат |
|---|---|---|---|---|
| Голяма продуктова отстъпка | 50 лв. | 100 лв. | 60 лв. | Пази намалената (50 лв.) |
| Малка продуктова отстъпка | 90 лв. | 100 лв. | 60 лв. | Ползва промото (60 лв.) |
| Без отстъпка | 100 лв. | 100 лв. | 60 лв. | Ползва промото (60 лв.) |

Ако `it_osnovna_cena = 0` (артикулът няма каталожна цена) — промото се прилага върху намалената цена като fallback.

</details>

<details>
<summary><b>🧮 fixed тип — ваучер</b></summary>

```
discount = min(voucher_remainer, subtotal)
```

`voucher_remainer` намалява при всяка употреба (общ бюджет, не per-user).

</details>

<details>
<summary><b>🧮 shipping тип</b></summary>

```
deduction = shipping_cap IS NULL ? full_shipping : min(shipping_cap, shipping_cost)
```

</details>

---

## Валидации при прилагане на код

1. Код съществува и е активен (`active = 1`)
2. Не е изтекъл (string compare `expiration_date` срещу `date('YmdHis')`)
3. Количката покрива `min_subtotal`
4. Кодът не е вече приложен в тази количка
5. `stack_group` конфликт — само 1 код от групата
6. `max_uses` — `times_used < max_uses`
7. `fixed` тип — `voucher_remainer > 0`

---

## Извършени стъпки

<details>
<summary><b>Step 0 — Open questions resolved + pre-flight checks</b></summary>

**Решения:**

| Въпрос | Решение | Основание |
|---|---|---|
| `potrebitel` колоната | **DROP** | 0/18 distinct non-zero стойности match `klienti.klienti_id`. Никой PHP файл не чете тази колона. Dead data. |
| `sait` (multi-site) | **KEEP** | Реален сценарий с bg/ro/gr/all стойности. |
| `active` за `obshti_kodove` | `IF(data_validen > date('YmdHis'), 1, 0)` | Автоматично деактивиране на изтекли. |
| Историческ audit за used loyality_points | **IGNORE** | За `izpolzvan='1'` редовете нямаме `order_id`. |

**Pre-flight резултати:**

| Check | loyality_points | obshti_kodove |
|---|---|---|
| Total rows | 16,221 | 17 |
| MAX(LENGTH(kod)) | 14 | 12 |
| NULL/bad tip | 0 | **3** (test rows) |
| Empty kod | 0 | 0 |
| Bad date format | 0 | 0 |
| Code collisions между таблиците | 0 | — |

**Експектация:** 16,221 + 14 = 16,235 реда в `promo_codes`.

</details>

<details>
<summary><b>Step 1 — Update master plan with decisions</b></summary>

- Замених секция "Отворени въпроси" в `promo-codes-master-plan.md` с разрешените отговори.
- Update на migration SQL: `obshti_kodove.active` използва `IF(data_validen > NOW, 1, 0)` вместо твърдо `1`.
- В migration-а — PHP-style `date('YmdHis')` → MySQL `DATE_FORMAT(NOW(),'%Y%m%d%H%i%s')`.

**Файлове:** `promo-codes-master-plan.md`

</details>

<details>
<summary><b>Step 2 — Update promo-codes-docs.md</b></summary>

- `remaining_amount` → `voucher_remainer`
- Date колони → `VARCHAR(14)` `YYYYMMDDHHmmss`
- Добавени: `created_at`, `used_at`, `source`, `note`, `site`, `created_by`
- `cart_promo_codes.created_at` и `order_promo_codes.created_at` като `VARCHAR(14) NOT NULL`
- Бележка за string-based date comparison (`strtotime` → директно `<`)

**Файлове:** `mysql-dumps/promo-codes-docs.md`

</details>

<details>
<summary><b>Step 3 — Rewrite DDL file</b></summary>

- Презаписах `public_html/citte/api/promo-validate-table.sql` с новата schema.
- Старата DDL имаше само `promo_codes` + `order_promo_codes`; новата добавя и `cart_promo_codes` (вече я има в production като TIMESTAMP, сега VARCHAR(14)).
- Тестовите INSERT-и обогатени с `created_at`, `source`, `created_by`, `note`.
- За `FLAT5` (fixed type) — отделен UPDATE за `voucher_remainer`.
- `CREATE TABLE IF NOT EXISTS` — safe за повторно изпълнение.

**Файлове:** `public_html/citte/api/promo-validate-table.sql`

</details>

<details>
<summary><b>Step 4 — Execute migration on dev imartap</b></summary>

CREATE TABLE → START TRANSACTION → INSERT IGNORE (loyality) → INSERT IGNORE (obshti) → COMMIT → verification.

```
== COUNTS ==
loyality_count: 16221
obshti_count:   17
promo_count:    16235
from_marketer:  16221
from_manual:    14    (3 test-rows с NULL tip филтрирани)

== TYPE DISTRIBUTION ==
the-marketer: percent=16144, fixed=76, shipping=1
manual:       percent=12,    fixed=1,  shipping=1

== ACTIVE FLAG ==
the-marketer: active=1 → 16136, active=0 → 85 (исторически used)
manual:       active=1 → 6,     active=0 → 8  (изтекли)

== VOUCHER_REMAINER SANITY ==
percent:  16156 общо / 16156 NULL  ✓
fixed:    77 общо    / 0 NULL      ✓
shipping: 2 общо     / 2 NULL      ✓
```

**Файлове:** DB `imartap` — създадени `promo_codes`, `cart_promo_codes`, `order_promo_codes`. Старите таблици touch-free.

</details>

<details>
<summary><b>Step 5 — Rewrite the-marketer/promo-codes.php</b></summary>

- INSERT в `loyality_points` → INSERT в `promo_codes`.
- Добавени: type ENUM mapping, `voucher_remainer` (за fixed), `max_uses=1`, `active=1`, `source='the-marketer'`, `created_by='the-marketer'`.
- JSON response непроменен — The Marketer не вижда промяна.

**Файлове:** `public_html/citte/the-marketer/promo-codes.php`

</details>

<details>
<summary><b>Step 6 — Refactor PromoCode.php</b></summary>

- Глобален rename `remaining_amount` → `voucher_remainer`.
- `validate()` expiration: `strtotime($r['expiration_date']) < strtotime('today')` → string compare `$r['expiration_date'] < date('YmdHis')`.
- `markUsed()`: добавен UPDATE на `promo_codes.used_at = date('YmdHis')`.
- INSERT в `order_promo_codes` сега включва `created_at`.

**Файлове:** `public_html/citte/lib/PromoCode.php`
**Verification:** `grep "remaining_amount\|strtotime"` → 0 hits.

</details>

<details>
<summary><b>Step 7 — Add created_at to cart/order INSERTs</b></summary>

- `promo-cart.php`: INSERT INTO `cart_promo_codes` включва `created_at = date('YmdHis')`.
- `PromoCode::markUsed()`: вече беше fix-нат в Step 6.
- `promo-validate.php` — не пипа pivot tables, no change.

**Файлове:** `public_html/citte/api/promo-cart.php`

</details>

<details>
<summary><b>Step 8 — Fix consumers of getAppliedForCart()</b></summary>

- Grep `remaining_amount` в `public_html/citte/` → 0 hits.
- Grep в `case.php`, `promo-input.php`, `promo-cart-rows.php` → 0 hits.
- UI компонентите разчитат само на `discount_applied` от `cart_promo_codes`.

**Файлове:** няма (no changes needed).

</details>

<details>
<summary><b>Step 9 — Apply new schema to per-site DBs (inmarta, iimarta)</b></summary>

**Runtime error на bg site:**
```
Fatal error: Uncaught mysqli_sql_exception: Unknown column 'pc.voucher_remainer'
in 'field list' in PromoCode.php:162
```

**Root cause:** master plan мигрира към `imartap.promo_codes`, но bg cart flow (`zaskiba.php:29 $zuttrttuz="bg"` → `zamysql.php:8 $msql_bgbasa='inmarta'`) използва `inmarta`. `inmarta.promo_codes` все още беше със старата schema (`remaining_amount`, `expiration_date DATE`, без `created_at`/`used_at`/`source`/`note`/`site`/`created_by`); `inmarta.cart_promo_codes.created_at` беше `TIMESTAMP`.

**Pre-action counts:**
- `inmarta`: 10 promo_codes (само dev seed), 1 cart_promo_codes (test ред), 0 order_promo_codes
- `iimarta`: нямаше нито една от трите таблици

**Действия:** `DROP TABLE IF EXISTS cart_promo_codes, order_promo_codes, promo_codes` в `inmarta`. Изпълних `public_html/citte/api/promo-validate-table.sql` срещу `inmarta` и `iimarta`. Verified чрез `SHOW COLUMNS`.

**Open architectural question:** Мигрираните 16,235 реда седят в `imartap.promo_codes` и **не са** достъпни от bg/gr cart. Бъдеще: cross-DB copy, или single source `imartap.promo_codes` с cross-DB JOIN, или преосмисляне на архитектурата.

</details>

<details>
<summary><b>Step 10 — Drop max_uses_per_user, add times_used counter</b></summary>

По обратна връзка от колегата — премахваме per-user limit функционалността и заменяме COUNT-based `max_uses` check с явен брояч.

**PHP** (`PromoCode.php`):
- Drop per-user limit block в `validate()`.
- SELECT добавя `times_used`.
- `max_uses` check: `(int)$r['times_used'] >= (int)$r['max_uses']` (no COUNT subquery).
- `markUsed()` UPDATE: `used_at = $now, times_used = times_used + 1`.

**DDL** (`promo-validate-table.sql`, `01-create-promo_codes.sql`, `03-create-order_promo_codes.sql` comments, `promo-codes-docs.md`, `promo-codes-master-plan.md`):
- `max_uses_per_user` → `times_used INT NOT NULL DEFAULT 0`.

**DB ALTER** (приложен на трите DB):
```sql
ALTER TABLE imartap.promo_codes
  DROP COLUMN max_uses_per_user,
  ADD COLUMN times_used INT NOT NULL DEFAULT 0 AFTER max_uses;
ALTER TABLE inmarta.promo_codes  ...same...
ALTER TABLE iimarta.promo_codes  ...same...
```

Row counts непроменени: 16,235 / 4 / 4. Историческите 85 the-marketer `active=0` rows са filtered от `active` check преди `max_uses` сравнение — safe.

**Бележки:**
- `klienti_id` колоната в `order_promo_codes` остава (за audit/analytics).
- `idx_klienti` index — все още е там; малък overhead, може да се drop-не при cleanup.

</details>

---

## SQL стъпки за реализация (canonical scripts)

Файловете живеят в `mysql-dumps/promo_codes/`. Изпълнение в ред: **01 → 02 → 03 → 04 → 05 → 06 → 07**.

<details>
<summary><b>01-create-promo_codes.sql</b> — главна таблица</summary>

```sql
USE imartap;
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS `promo_codes`;

CREATE TABLE `promo_codes` (
  `id`                INT           NOT NULL AUTO_INCREMENT,
  `code`              VARCHAR(50)   NOT NULL,
  `type`              ENUM('percent','fixed','shipping') NOT NULL DEFAULT 'percent',

  -- Стойност
  `discount_value`    DECIMAL(10,2) NOT NULL,
  `voucher_remainer`  DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'само за fixed — бюджет, намалява при употреба',

  -- Ограничения
  `min_subtotal`      DECIMAL(10,2) NOT NULL DEFAULT 0,
  `shipping_cap`      DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'само за shipping (NULL = без cap)',
  `max_uses`          INT           NOT NULL DEFAULT 0 COMMENT '0 = безлимит',
  `times_used`        INT           NOT NULL DEFAULT 0 COMMENT 'брояч на употреби; ++ при markUsed()',

  -- Поведение
  `active`            BOOLEAN       NOT NULL DEFAULT TRUE,
  `stack_group`       TINYINT       NULL DEFAULT NULL COMMENT 'NULL = комбинира се с всичко',

  -- Дати (всички VARCHAR(14) YYYYMMDDHHmmss)
  `expiration_date`   VARCHAR(14)   NULL DEFAULT NULL,
  `created_at`        VARCHAR(14)   NOT NULL,
  `used_at`           VARCHAR(14)   NULL DEFAULT NULL COMMENT 'last-used; update-ва се при markUsed()',

  -- Произход / метадата
  `source`            ENUM('the-marketer','manual','bulk-import') NOT NULL DEFAULT 'manual',
  `note`              VARCHAR(255)  NULL DEFAULT NULL COMMENT 'бивш komentar',
  `site`              VARCHAR(10)   NULL DEFAULT NULL COMMENT 'бивш sait — bg/ro/gr/all',
  `created_by`        VARCHAR(255)  NULL DEFAULT NULL COMMENT 'бивш ot_kade — free-form audit',

  PRIMARY KEY (`id`),
  UNIQUE KEY `code` (`code`),
  KEY `idx_active_exp` (`active`, `expiration_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
```

</details>

<details>
<summary><b>02-create-cart_promo_codes.sql</b> — pivot за активна количка</summary>

```sql
USE imartap;
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS `cart_promo_codes`;

CREATE TABLE `cart_promo_codes` (
  `id`               INT           NOT NULL AUTO_INCREMENT,
  `cart_id`          INT           NOT NULL,
  `cart_type`        ENUM('l','no') NOT NULL COMMENT "'l' = porachki_l (logged-in), 'no' = porachki_no (guest)",
  `promo_code_id`    INT           NOT NULL,
  `code`             VARCHAR(50)   NOT NULL,
  `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '0 за type=shipping; реална deduction за percent/fixed',
  `type`             ENUM('percent','fixed','shipping') NOT NULL,
  `shipping_cap`     DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'само за type=shipping',
  `created_at`       VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_cart_promo` (`cart_id`, `cart_type`, `promo_code_id`),
  CONSTRAINT `fk_cpc_promo` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
```

</details>

<details>
<summary><b>03-create-order_promo_codes.sql</b> — pivot за финализирани употреби</summary>

```sql
USE imartap;
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS `order_promo_codes`;

CREATE TABLE `order_promo_codes` (
  `id`               INT           NOT NULL AUTO_INCREMENT,
  `order_id`         INT           NOT NULL COMMENT 'porachki.porachki_id',
  `promo_code_id`    INT           NOT NULL,
  `klienti_id`       INT           NOT NULL DEFAULT 0 COMMENT '0 = гост',
  `discount_applied` DECIMAL(10,2) NOT NULL,
  `created_at`       VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_order_promo` (`order_id`, `promo_code_id`),
  KEY `idx_klienti` (`klienti_id`, `promo_code_id`),
  CONSTRAINT `fk_opc_promo` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
```

Insert-ва се от `PromoCode::markUsed()` при потвърдена поръчка. Глобалният брояч `promo_codes.times_used` се incrementерва паралелно.

</details>

<details>
<summary><b>04-pre-flight-checks.sql</b> — diagnostics преди migration</summary>

```sql
USE imartap;

-- 1. Кодове по-дълги от 50 символа?
SELECT 'loyality_points' AS tbl, MAX(LENGTH(kod)) AS max_len, COUNT(*) AS total FROM loyality_points
UNION ALL
SELECT 'obshti_kodove'    AS tbl, MAX(LENGTH(kod)) AS max_len, COUNT(*) AS total FROM obshti_kodove;

-- 2. NULL или невалидни tip стойности
SELECT 'loyality NULL/bad tip' AS lbl, COUNT(*) AS cnt FROM loyality_points WHERE tip IS NULL OR tip NOT IN (0,1,2)
UNION ALL
SELECT 'obshti NULL/bad tip'    AS lbl, COUNT(*) AS cnt FROM obshti_kodove   WHERE tip IS NULL OR tip NOT IN (0,1,2);

-- 3. Code collisions между двете таблици
SELECT l.kod AS colliding_code, l.id AS loyality_id, o.id AS obshti_id
FROM loyality_points l
JOIN obshti_kodove o ON l.kod = o.kod;

-- 4. Невалидни (празни/NULL) кодове
SELECT 'loyality empty kod' AS lbl, COUNT(*) AS cnt FROM loyality_points WHERE kod IS NULL OR kod = ''
UNION ALL
SELECT 'obshti empty kod'    AS lbl, COUNT(*) AS cnt FROM obshti_kodove   WHERE kod IS NULL OR kod = '';

-- 5. data_validen формат — всички ли са 14-цифрен YYYYMMDDHHmmss
SELECT 'loyality bad date' AS lbl, COUNT(*) AS cnt FROM loyality_points
  WHERE data_validen IS NOT NULL
    AND (LENGTH(data_validen) <> 14 OR data_validen NOT REGEXP '^[0-9]{14}$')
UNION ALL
SELECT 'obshti bad date'    AS lbl, COUNT(*) AS cnt FROM obshti_kodove
  WHERE data_validen IS NOT NULL
    AND (LENGTH(data_validen) <> 14 OR data_validen NOT REGEXP '^[0-9]{14}$');

-- 6. Baseline counts
SELECT 'loyality_points'      AS tbl, COUNT(*) AS total FROM loyality_points
UNION ALL
SELECT 'obshti_kodove'        AS tbl, COUNT(*) AS total FROM obshti_kodove
UNION ALL
SELECT 'promo_codes (before)' AS tbl, COUNT(*) AS total FROM promo_codes;
```

На база резултатите решаваме: вдигане на `code` лимита, филтриране на NULL tip, pre-empt-ване на code collisions, почистване на празни kod / невалиден date формат.

</details>

<details>
<summary><b>05-migrate-loyality_points.sql</b> — single-use The Marketer codes</summary>

```sql
USE imartap;

INSERT IGNORE INTO promo_codes
  (code, type, discount_value, voucher_remainer,
   max_uses, active,
   expiration_date, created_at, used_at,
   source, note, site, created_by)
SELECT
   kod,
   CASE tip WHEN 0 THEN 'fixed' WHEN 1 THEN 'percent' WHEN 2 THEN 'shipping' ELSE 'percent' END,
   CAST(value AS DECIMAL(10,2)),
   CASE WHEN tip = 0 THEN CAST(value AS DECIMAL(10,2)) ELSE NULL END,
   1,                                              -- single-use
   IF(izpolzvan = '1', 0, 1),                      -- използваният → неактивен
   data_validen,
   data_sazdaden,
   data_izpolzvan,
   'the-marketer',
   komentar,
   sait,
   COALESCE(NULLIF(ot_kade, ''), 'the-marketer')
FROM loyality_points
WHERE kod IS NOT NULL AND kod <> ''
  AND tip IN (0, 1, 2);
```

`INSERT IGNORE` — пропуска редове, които биха нарушили UNIQUE на `code`. `WHERE tip IN (0,1,2)` — изключва NULL/невалидни.

</details>

<details>
<summary><b>06-migrate-obshti_kodove.sql</b> — multi-use manual codes</summary>

```sql
USE imartap;

INSERT IGNORE INTO promo_codes
  (code, type, discount_value, voucher_remainer,
   max_uses, active,
   expiration_date, created_at, used_at,
   source, note, site, created_by)
SELECT
   kod,
   CASE tip WHEN 0 THEN 'fixed' WHEN 1 THEN 'percent' WHEN 2 THEN 'shipping' ELSE 'percent' END,
   CAST(value AS DECIMAL(10,2)),
   CASE WHEN tip = 0 THEN CAST(value AS DECIMAL(10,2)) ELSE NULL END,
   0,                                              -- multi-use (безлимит)
   IF(data_validen > DATE_FORMAT(NOW(),'%Y%m%d%H%i%s'), 1, 0),
   data_validen,
   data_sazdaden,
   NULL,                                           -- няма last-used в obshti_kodove
   'manual',
   komentar,
   sait,
   NULLIF(ot_kade, '')
FROM obshti_kodove
WHERE kod IS NOT NULL AND kod <> ''
  AND tip IN (0, 1, 2);
```

`active` се изчислява динамично — изтеклите автоматично стават неактивни.

</details>

<details>
<summary><b>07-verification.sql</b> — sanity checks след migration</summary>

```sql
USE imartap;

-- Aggregate counts — overview
SELECT
   (SELECT COUNT(*) FROM loyality_points)                          AS loyality_total,
   (SELECT COUNT(*) FROM obshti_kodove)                            AS obshti_total,
   (SELECT COUNT(*) FROM promo_codes)                              AS promo_total,
   (SELECT COUNT(*) FROM promo_codes WHERE source='the-marketer')  AS from_marketer,
   (SELECT COUNT(*) FROM promo_codes WHERE source='manual')        AS from_manual,
   (SELECT COUNT(*) FROM promo_codes WHERE source='bulk-import')   AS from_bulk;

-- Mismatches — кодове в старите таблици, които НЕ са в promo_codes
SELECT 'missing from loyality' AS lbl, l.id, l.kod
  FROM loyality_points l
  LEFT JOIN promo_codes p ON p.code = l.kod
  WHERE p.id IS NULL AND l.kod IS NOT NULL AND l.kod <> ''
UNION ALL
SELECT 'missing from obshti' AS lbl, o.id, o.kod
  FROM obshti_kodove o
  LEFT JOIN promo_codes p ON p.code = o.kod
  WHERE p.id IS NULL AND o.kod IS NOT NULL AND o.kod <> '';

-- Spot checks — известни кодове
SELECT id, code, type, discount_value, voucher_remainer, max_uses, active,
       expiration_date, created_at, used_at, source, created_by, note
FROM promo_codes
WHERE code IN ('VELIKDEN10','slujeben10','SPRING10EM26','svet25evro','svet10procenta','kod0','kod1')
ORDER BY source, code;

-- Type distribution по източник
SELECT source, type, COUNT(*) AS cnt
FROM promo_codes GROUP BY source, type ORDER BY source, type;

-- Active distribution по източник
SELECT source, active, COUNT(*) AS cnt
FROM promo_codes GROUP BY source, active ORDER BY source, active;

-- Sanity: voucher_remainer само за fixed type
SELECT 'voucher_remainer set for non-fixed' AS lbl, COUNT(*) AS cnt
FROM promo_codes WHERE voucher_remainer IS NOT NULL AND type <> 'fixed';
-- Очаквано: 0

-- Sanity: всеки fixed type има voucher_remainer
SELECT 'fixed type without voucher_remainer' AS lbl, COUNT(*) AS cnt
FROM promo_codes WHERE type = 'fixed' AND voucher_remainer IS NULL;
-- Очаквано: 0

-- Sanity: created_at винаги е попълнен
SELECT 'rows missing created_at' AS lbl, COUNT(*) AS cnt
FROM promo_codes WHERE created_at IS NULL OR created_at = '';
-- Очаквано: 0
```

</details>

<details>
<summary><b>ALTER за съществуващи DB (Step 10)</b> — drop max_uses_per_user, add times_used</summary>

Прилага се след `01-create-promo_codes.sql` ако таблицата вече съществува със старата схема.

```sql
ALTER TABLE imartap.promo_codes
  DROP COLUMN max_uses_per_user,
  ADD COLUMN times_used INT NOT NULL DEFAULT 0 AFTER max_uses;

ALTER TABLE inmarta.promo_codes
  DROP COLUMN max_uses_per_user,
  ADD COLUMN times_used INT NOT NULL DEFAULT 0 AFTER max_uses;

ALTER TABLE iimarta.promo_codes
  DROP COLUMN max_uses_per_user,
  ADD COLUMN times_used INT NOT NULL DEFAULT 0 AFTER max_uses;
```

Историческите `active=0` rows са filtered от `active` check преди `max_uses` сравнение — backfill на `times_used` не е нужен.

</details>

---

## Стари таблици (deprecated, read-only)

`loyality_points` и `obshti_kodove` остават след миграцията само за reference / audit / reconciliation срещу external systems (The Marketer dashboard). PHP кодът не пише и не чете от тях.

| Стара таблица | Брой редове | Замяна |
|---|---|---|
| `loyality_points` | 16,221 | `promo_codes` (source='the-marketer', max_uses=1) |
| `obshti_kodove` | 17 (3 test-rows с NULL tip се изключват) | `promo_codes` (source='manual', max_uses=0) |

---

## Open items

- **Cross-DB dataflow**: Мигрираните 16,235 реда седят в `imartap.promo_codes`, но bg/gr cart използват `inmarta`/`iimarta`. Бъдеще: cross-DB copy, или single source `imartap` с cross-DB JOIN, или преосмисляне.
- **`idx_klienti` index** в `order_promo_codes` е dead без `max_uses_per_user`; малък overhead, може да се drop-не при cleanup.
- **Тестови seed кодове** (TEST10/SUMMER20/FLAT5/FREESHIP) в DDL — изтрий или пропусни DDL преди production deploy.
