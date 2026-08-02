# Promocodes Github Comment

## Промо кодове — миграции за дев среда

**Предпоставка:** база без нищо промо-related (оригинална схема, преди каквато и да е промо/цена миграция).

### Ред на пускане

```
регионална (inmarta):  00 → 01 → 02 → 03 → 04 → 05 → 10
imartap:               00 → 03 → 04 → 06 → 09 → 07 → 08 → 10
```

Зависимости в imartap: **06 преди 07** (FK сочи `promo_codes.id`), **06 преди 08** (seed-ва в `promo_codes`), **09 преди 08** (иначе лек/EUR конверсията пада на 1.0 и seed-ът изглежда счупен).

### Файлове

|     |     |     |     |     |
| --- | --- | --- | --- | --- |
| #   | Файл | Регионална | imartap | Какво |
| 00  | `00-preflight.sql` | ✅   | ✅   | **Read-only.** Проверява, че базата е от нула |
| 01  | `01-create-cart_promo_codes.sql` | ✅   | —   | `cart_promo_codes` |
| 02  | `02-create-order_promo_codes.sql` | ✅   | —   | `order_promo_codes` (без FK) |
| 03  | `03-add-item-promo-columns.sql` | ✅   | ✅   | `item`/`item_l`/`item_no`: 5 промо колони |
| 04  | `04-add-porachki-promo-columns.sql` | ✅   | ✅   | `porachki*`: `pordost_coupon_discount`, `promo_fixed_discount` |
| 05  | `05-seed-catalog-promo-skus.sql` | ✅   | —   | 4 промо SKU в `catalog` |
| 06  | `06-create-imartap-promo_codes.sql` | —   | ✅   | `promo_codes` (каталогът) |
| 07  | `07-create-imartap-order_promo_codes.sql` | —   | ✅   | `order_promo_codes` **с** FK |
| 08  | `08-seed-imartap-promo_codes.sql` | —   | ✅   | 7 example кода (опционален) |
| 09  | `09-create-imartap-currency_rates.sql` | —   | ✅   | `currency_rates` + 4 реда |
| 10  | `10-verify.sql` | ✅   | ✅   | **Read-only.** Какво реално е кацнало |

### Самите миграции

<details>
<summary><b>00-preflight.sql</b> — read-only, проверява че базата е от нула (регионална + imartap)</summary>

```sql
-- =============================================================================
-- 00 — PRE-FLIGHT (read-only, writes NOTHING)
-- Target: EVERY DB you are about to migrate — regional AND imartap.
-- Run: mysql -D <db> --table < 00-preflight.sql
--
-- The rest of this set is plain, unguarded SQL: the first bad statement aborts the
-- file and leaves the earlier statements applied. This file proves up-front that
-- the target really is a from-zero environment, so that never happens.
--
-- EVERY row of every check must read OK. A single FAIL means this DB is NOT a
-- fresh target — it has been through the historical migration path (or a partial
-- fresh run). Do NOT continue; reconcile by hand or use ../../deploy/* instead.
--
-- The checks are written against information_schema, so a missing table is simply
-- a zero count, not an error — a regional DB legitimately has no `porachki` master
-- and imartap legitimately has no `item_l`/`item_no`/`catalog`. Those show up as
-- "n/a (table absent here)", which is NOT a failure.
-- =============================================================================

SELECT DATABASE() AS `db`, VERSION() AS `mysql_version`, NOW() AS `checked_at`;


-- ── 1. Which of the tables this set touches exist here? ──────────────────────
-- Tells you which target you are on. Regional expects: catalog, item, item_l,
-- item_no, porachki, porachki_l, porachki_no. imartap expects: item, porachki.
SELECT
  'A. tables present' AS `check`,
  TABLE_NAME          AS `table`,
  TABLE_ROWS          AS `approx_rows`
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('catalog','item','item_l','item_no',
                     'porachki','porachki_l','porachki_no')
ORDER BY TABLE_NAME;


-- ── 2. None of the promo tables may exist yet ────────────────────────────────
-- Created by 01/02 (regional) and 06/07/09 (imartap).
SELECT
  'B. promo tables absent' AS `check`,
  t.`name`                 AS `table`,
  IF(c.TABLE_NAME IS NULL, 'OK', 'FAIL — already exists') AS `result`
FROM (
  SELECT 'promo_codes' AS `name`
  UNION ALL SELECT 'cart_promo_codes'
  UNION ALL SELECT 'order_promo_codes'
  UNION ALL SELECT 'currency_rates'
) t
LEFT JOIN information_schema.TABLES c
       ON c.TABLE_SCHEMA = DATABASE()
      AND c.TABLE_NAME   = t.`name`
ORDER BY t.`name`;


-- ── 3. item* baseline: ORIGINAL stored it_cena / it_suma ─────────────────────
-- File 03 is additive on top of these. On a DB that went through the historical
-- path they are VIRTUAL generated columns (EXTRA contains 'GENERATED') — that is
-- the single clearest tell that this is NOT a fresh target.
SELECT
  'C. it_cena/it_suma are original stored cols' AS `check`,
  t.`name`     AS `table`,
  t.`col`      AS `column`,
  CASE
    WHEN tt.TABLE_NAME IS NULL         THEN 'n/a (table absent here)'
    WHEN col.COLUMN_NAME IS NULL       THEN 'FAIL — column missing'
    WHEN col.EXTRA LIKE '%GENERATED%'  THEN CONCAT('FAIL — generated: ', col.EXTRA)
    ELSE CONCAT('OK — stored ', col.COLUMN_TYPE)
  END AS `result`
FROM (
            SELECT 'item'    AS `name`, 'it_cena' AS `col`
  UNION ALL SELECT 'item',              'it_suma'
  UNION ALL SELECT 'item_l',            'it_cena'
  UNION ALL SELECT 'item_l',            'it_suma'
  UNION ALL SELECT 'item_no',           'it_cena'
  UNION ALL SELECT 'item_no',           'it_suma'
) t
LEFT JOIN information_schema.TABLES tt
       ON tt.TABLE_SCHEMA = DATABASE()
      AND tt.TABLE_NAME   = t.`name`
LEFT JOIN information_schema.COLUMNS col
       ON col.TABLE_SCHEMA = DATABASE()
      AND col.TABLE_NAME   = t.`name`
      AND col.COLUMN_NAME  = t.`col`
ORDER BY t.`name`, t.`col`;


-- ── 4. No leftovers from the historical path, no promo columns yet ───────────
-- it_cena_baza / it_suma_baza : added by the old path, renamed away later.
-- it_cena_suma                : only ever existed mid-path; dropped at the end.
-- discount_applied … promot_new : added by 03 — must not be here yet.
SELECT
  'D. item* promo/legacy columns absent' AS `check`,
  t.`name`  AS `table`,
  t.`col`   AS `column`,
  CASE
    WHEN tt.TABLE_NAME IS NULL   THEN 'n/a (table absent here)'
    WHEN col.COLUMN_NAME IS NULL THEN 'OK'
    ELSE 'FAIL — already present'
  END AS `result`
FROM (
            SELECT 'item'    AS `name`, 'it_cena_baza'     AS `col`
  UNION ALL SELECT 'item',              'it_suma_baza'
  UNION ALL SELECT 'item',              'it_cena_suma'
  UNION ALL SELECT 'item',              'discount_applied'
  UNION ALL SELECT 'item',              'it_cena_new'
  UNION ALL SELECT 'item',              'it_suma_new'
  UNION ALL SELECT 'item',              'item_br_new'
  UNION ALL SELECT 'item',              'promot_new'
  UNION ALL SELECT 'item_l',            'it_cena_baza'
  UNION ALL SELECT 'item_l',            'it_suma_baza'
  UNION ALL SELECT 'item_l',            'it_cena_suma'
  UNION ALL SELECT 'item_l',            'discount_applied'
  UNION ALL SELECT 'item_l',            'it_cena_new'
  UNION ALL SELECT 'item_l',            'it_suma_new'
  UNION ALL SELECT 'item_l',            'item_br_new'
  UNION ALL SELECT 'item_l',            'promot_new'
  UNION ALL SELECT 'item_no',           'it_cena_baza'
  UNION ALL SELECT 'item_no',           'it_suma_baza'
  UNION ALL SELECT 'item_no',           'it_cena_suma'
  UNION ALL SELECT 'item_no',           'discount_applied'
  UNION ALL SELECT 'item_no',           'it_cena_new'
  UNION ALL SELECT 'item_no',           'it_suma_new'
  UNION ALL SELECT 'item_no',           'item_br_new'
  UNION ALL SELECT 'item_no',           'promot_new'
) t
LEFT JOIN information_schema.TABLES tt
       ON tt.TABLE_SCHEMA = DATABASE()
      AND tt.TABLE_NAME   = t.`name`
LEFT JOIN information_schema.COLUMNS col
       ON col.TABLE_SCHEMA = DATABASE()
      AND col.TABLE_NAME   = t.`name`
      AND col.COLUMN_NAME  = t.`col`
ORDER BY t.`name`, t.`col`;


-- ── 5. porachki* promo columns must not exist yet (added by 04) ──────────────
SELECT
  'E. porachki* promo columns absent' AS `check`,
  t.`name`  AS `table`,
  t.`col`   AS `column`,
  CASE
    WHEN tt.TABLE_NAME IS NULL   THEN 'n/a (table absent here)'
    WHEN col.COLUMN_NAME IS NULL THEN 'OK'
    ELSE 'FAIL — already present'
  END AS `result`
FROM (
            SELECT 'porachki'    AS `name`, 'pordost_coupon_discount' AS `col`
  UNION ALL SELECT 'porachki_l',            'pordost_coupon_discount'
  UNION ALL SELECT 'porachki_l',            'promo_fixed_discount'
  UNION ALL SELECT 'porachki_no',           'pordost_coupon_discount'
  UNION ALL SELECT 'porachki_no',           'promo_fixed_discount'
) t
LEFT JOIN information_schema.TABLES tt
       ON tt.TABLE_SCHEMA = DATABASE()
      AND tt.TABLE_NAME   = t.`name`
LEFT JOIN information_schema.COLUMNS col
       ON col.TABLE_SCHEMA = DATABASE()
      AND col.TABLE_NAME   = t.`name`
      AND col.COLUMN_NAME  = t.`col`
ORDER BY t.`name`, t.`col`;


-- ── 6. Engine sanity ────────────────────────────────────────────────────────
-- 07 adds real FKs, so InnoDB must be available.
SELECT
  'F. InnoDB available' AS `check`,
  ENGINE               AS `engine`,
  SUPPORT              AS `support`,
  IF(SUPPORT IN ('YES','DEFAULT'), 'OK', 'FAIL — 07 needs InnoDB for the FKs') AS `result`
FROM information_schema.ENGINES
WHERE ENGINE = 'InnoDB';


-- ── 7. catalog promo SKUs must not be seeded yet (added by 05) ───────────────
-- `catalog` has no UNIQUE KEY on cat_no, so 05 cannot protect itself — this query
-- is the only guard against a silent duplicate seed. Expected: Empty set.
-- Any row returned = FAIL, 05 has already run here.
--
-- REGIONAL DBs ONLY. Every check above reads information_schema and runs anywhere;
-- this last one reads `catalog` itself, so on imartap it raises ERROR 1146. Nothing
-- is written either way and it is deliberately the LAST statement, so just ignore
-- that error on imartap (or run the file with --force). Check A tells you which
-- target you are on. NEVER use --force on the migration files 01-09.
SELECT 'G. catalog promo SKUs absent' AS `check`,
       `cat_no`, `ime`, `vidimost`, `p_acti`
FROM `catalog`
WHERE `cat_no` IN ('5555555','6666666','7777777','8888888');
```

</details>

<details>
<summary><b>01-create-cart_promo_codes.sql</b> — <code>cart_promo_codes</code> (регионална)</summary>

```sql
-- =============================================================================
-- 01 — cart_promo_codes (regional cart pivot)
-- Target: regional DB (Albania). imartap catalog is shared / out of scope.
-- Run: mysql -D <regional_db> < 01-create-cart_promo_codes.sql
--
-- Plain SQL, no guards, no prepared statements. NOT idempotent: on a re-run or a
-- non-empty target MySQL raises an error and aborts — that error is the signal.
-- Baseline: a DB with NOTHING promo-related (original pre-migration schema).
--
-- promo_code_id -> imartap.promo_codes.id: no cross-DB FK (intentional).
-- =============================================================================

CREATE TABLE `cart_promo_codes` (
  `id`               INT           NOT NULL AUTO_INCREMENT,
  `cart_id`          INT           NOT NULL,
  `cart_type`        ENUM('l','no') NOT NULL COMMENT 'l = porachki_l (logged-in), no = porachki_no (guest)',
  `promo_code_id`    INT           NOT NULL COMMENT 'imartap.promo_codes.id (no cross-DB FK)',
  `code`             VARCHAR(50)   NOT NULL,
  `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT '0.00' COMMENT '0 for shipping types — real deduction for percent/fixed',
  `discount_value`   DECIMAL(10,2) NOT NULL DEFAULT '0.00' COMMENT 'snapshot of promo_codes.discount_value at apply-time',
  `currency`         ENUM('BGN','EUR','ALL','RON') NOT NULL DEFAULT 'BGN' COMMENT 'snapshot of promo_codes.currency at apply-time',
  `type`             ENUM('percent','fixed','shipping','shipping_percent') NOT NULL,
  `subtype`          ENUM('voucher','coupon') DEFAULT NULL,
  `shipping_cap`     DECIMAL(10,2) DEFAULT NULL COMMENT 'shipping/shipping_percent only (flat cap on the discount)',
  `created_at`       VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_cart_promo` (`cart_id`,`cart_type`,`promo_code_id`),
  KEY `idx_promo_code` (`promo_code_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

</details>

<details>
<summary><b>02-create-order_promo_codes.sql</b> — <code>order_promo_codes</code> без FK (регионална)</summary>

```sql
-- =============================================================================
-- 02 — order_promo_codes (regional order history)
-- Target: regional DB (Albania). imartap catalog is shared / out of scope.
-- Run: mysql -D <regional_db> < 02-create-order_promo_codes.sql
--
-- Plain SQL, no guards, no prepared statements. NOT idempotent: on a re-run or a
-- non-empty target MySQL raises an error and aborts — that error is the signal.
-- Baseline: a DB with NOTHING promo-related (original pre-migration schema).
--
-- promo_code_id -> imartap.promo_codes.id: no cross-DB FK (intentional).
-- =============================================================================

CREATE TABLE `order_promo_codes` (
  `id`                 INT           NOT NULL AUTO_INCREMENT,
  `order_id`           INT           NOT NULL COMMENT 'porachki.porachki_id',
  `promo_code_id`      INT           NOT NULL COMMENT 'imartap.promo_codes.id (no cross-DB FK)',
  `klienti_id`         INT           NOT NULL DEFAULT '0' COMMENT '0 = guest',
  `discount_applied`   DECIMAL(10,2) NOT NULL,
  `currency`           ENUM('BGN','EUR','ALL','RON') NOT NULL DEFAULT 'BGN' COMMENT 'snapshot of promo_codes.currency at order-finalize',
  `used_by_employeeId` INT           DEFAULT NULL COMMENT 'admin/backoffice app — storefront leaves NULL',
  `created_at`         VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_order_promo` (`order_id`,`promo_code_id`),
  KEY `idx_klienti` (`klienti_id`,`promo_code_id`),
  KEY `idx_promo_code` (`promo_code_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

</details>

<details>
<summary><b>03-add-item-promo-columns.sql</b> — 5 промо колони на <code>item</code>/<code>item_l</code>/<code>item_no</code></summary>

```sql
-- =============================================================================
-- 03 — item promo/price columns (item, item_l, item_no)
-- Target: ALL DBs — regional (item/item_l/item_no) AND imartap (item master).
-- Run:  mysql -D <regional_db> < 03-add-item-promo-columns.sql
--       mysql -D imartap       < 03-add-item-promo-columns.sql
--
-- Plain SQL, no guards, no prepared statements. NOT idempotent: on a re-run or a
-- non-empty target MySQL raises an error and aborts — that error is the signal.
-- Baseline: a DB with NOTHING promo-related (original pre-migration schema) — the
-- table already has the ORIGINAL stored price columns `it_cena` FLOAT and
-- `it_suma` FLOAT, and none of the promo columns below exist yet. Purely ADDITIVE.
--
-- Columns added:
--   discount_applied  DECIMAL(10,2)  per-line promo delta (cart writes it)
--   it_cena_new   FLOAT     )  Svetlyo/ERP-owned "final after promo" columns.
--   it_suma_new   FLOAT     )  NOT written by us — the storefront only READS them
--   item_br_new   INT       )  (moiteporachkipregled.php, v_cases.php).
--   promot_new    VARCHAR(20))
-- =============================================================================

-- ── item_l ───────────────────────────────────────────────────────────────────
ALTER TABLE `item_l`
  ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT 'promo discount applied to this line',
  ADD COLUMN `it_cena_new` FLOAT NULL DEFAULT NULL COMMENT 'Final unit price after promo — written by ERP',
  ADD COLUMN `it_suma_new` FLOAT NULL DEFAULT NULL COMMENT 'Final line total after promo — written by ERP',
  ADD COLUMN `item_br_new` INT NULL DEFAULT NULL COMMENT 'Final quantity after promo — written by ERP',
  ADD COLUMN `promot_new` VARCHAR(20) NULL DEFAULT NULL COMMENT 'Promo marker after promo — written by ERP';

-- ── item_no ──────────────────────────────────────────────────────────────────
ALTER TABLE `item_no`
  ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT 'promo discount applied to this line',
  ADD COLUMN `it_cena_new` FLOAT NULL DEFAULT NULL COMMENT 'Final unit price after promo — written by ERP',
  ADD COLUMN `it_suma_new` FLOAT NULL DEFAULT NULL COMMENT 'Final line total after promo — written by ERP',
  ADD COLUMN `item_br_new` INT NULL DEFAULT NULL COMMENT 'Final quantity after promo — written by ERP',
  ADD COLUMN `promot_new` VARCHAR(20) NULL DEFAULT NULL COMMENT 'Promo marker after promo — written by ERP';

-- ── item (finalized order lines; master in imartap + regional replica) ────────
ALTER TABLE `item`
  ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT 'promo discount applied to this line',
  ADD COLUMN `it_cena_new` FLOAT NULL DEFAULT NULL COMMENT 'Final unit price after promo — written by ERP',
  ADD COLUMN `it_suma_new` FLOAT NULL DEFAULT NULL COMMENT 'Final line total after promo — written by ERP',
  ADD COLUMN `item_br_new` INT NULL DEFAULT NULL COMMENT 'Final quantity after promo — written by ERP',
  ADD COLUMN `promot_new` VARCHAR(20) NULL DEFAULT NULL COMMENT 'Promo marker after promo — written by ERP';
```

</details>

<details>
<summary><b>04-add-porachki-promo-columns.sql</b> — <code>pordost_coupon_discount</code> + <code>promo_fixed_discount</code></summary>

```sql
-- =============================================================================
-- 04 — porachki promo columns (order + cart headers)
-- Target: ALL DBs — regional (porachki/porachki_l/porachki_no) AND imartap
--         (porachki master). Run against each DB that holds a porachki* table.
-- Run:  mysql -D <regional_db> < 04-add-porachki-promo-columns.sql
--       mysql -D imartap       < 04-add-porachki-promo-columns.sql
--
--   pordost_coupon_discount : porachki, porachki_l, porachki_no
--   promo_fixed_discount    : porachki_l, porachki_no ONLY (mini-cart net display)
--
-- Plain SQL, no guards, no prepared statements. NOT idempotent: on a re-run or a
-- non-empty target MySQL raises an error and aborts — that error is the signal.
-- Baseline: a DB with NOTHING promo-related (original pre-migration schema).
-- =============================================================================

-- ── pordost_coupon_discount : porachki / porachki_l / porachki_no ─────────────
ALTER TABLE `porachki`    ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT '0.00' COMMENT 'shipping-coupon discount on delivery cost';
ALTER TABLE `porachki_l`  ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT '0.00' COMMENT 'shipping-coupon discount on delivery cost';
ALTER TABLE `porachki_no` ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT '0.00' COMMENT 'shipping-coupon discount on delivery cost';

-- ── promo_fixed_discount : porachki_l / porachki_no ONLY ─────────────────────
ALTER TABLE `porachki_l`  ADD COLUMN `promo_fixed_discount` DECIMAL(10,2) NOT NULL DEFAULT '0.00' COMMENT 'Order-level fixed/voucher promo total on the cart (mini-cart net display)';
ALTER TABLE `porachki_no` ADD COLUMN `promo_fixed_discount` DECIMAL(10,2) NOT NULL DEFAULT '0.00' COMMENT 'Order-level fixed/voucher promo total on the cart (mini-cart net display)';
```

</details>

<details>
<summary><b>05-seed-catalog-promo-skus.sql</b> — ⚠️ 4 промо SKU в <code>catalog</code> (единственият без защита)</summary>

```sql
-- =============================================================================
-- 05 — catalog promo SKU seed (Microinvest negative rows)
-- Target: regional DB (Albania). catalog table lives in the regional DB.
-- Run: mysql -D <regional_db> < 05-seed-catalog-promo-skus.sql
--
-- Plain SQL, no guards. Baseline: a DB with NOTHING promo-related.
--
-- ⚠️ THE ONE FILE IN THIS SET WITH NO NATURAL RE-RUN PROTECTION. `catalog` has no
-- UNIQUE KEY on `cat_no`, so a second run does NOT error — it silently inserts a
-- duplicate of all four SKUs. Run it exactly once per regional DB. If you do run
-- it twice, undo with:
--     DELETE FROM `catalog` WHERE `cat_no` IN ('5555555','6666666','7777777','8888888');
-- and re-run this file. (Everything else in the set is protected: promo_codes.code
-- is UNIQUE, currency_rates.currency is the PK, the rest are bare CREATE TABLE.)
--
--   5555555 voucher/coupon      6666666 free shipping
--   7777777 coupon              8888888 percent discount
-- All cena = 0 (price carried by the promo row itself).
-- vidimost = 0 and p_acti = 0: the SKU must NOT be listable/orderable as a normal
-- product — the storefront guards on vidimost=0 so a shopper cannot add / bump the
-- quantity of a promo line by hand (see the memory / promo-codes docs).
-- NOTE: miarka is 'бр.' as in BG. Adjust the unit label if Albania differs.
--
-- SET NAMES utf8mb4 below is REQUIRED: without it a latin1 client connection
-- double-encodes the Cyrillic and stores mojibake (this is exactly how the live
-- BG catalog got corrupted). Keep it, or load with --default-character-set=utf8mb4.
-- =============================================================================

SET NAMES utf8mb4;

INSERT INTO `catalog` (`cat_no`, `ime`, `miarka`, `cena`, `vidimost`, `p_acti`, `nnindex`) VALUES
  ('5555555', 'Промо ваучер/купон',       'бр.', 0.00, 0, 0, 'promo-5555555'),
  ('6666666', 'Промо безплатна доставка', 'бр.', 0.00, 0, 0, 'promo-6666666'),
  ('7777777', 'Промо купон',              'бр.', 0.00, 0, 0, 'promo-7777777'),
  ('8888888', 'Промо процентна отстъпка', 'бр.', 0.00, 0, 0, 'promo-8888888');
```

</details>

<details>
<summary><b>06-create-imartap-promo_codes.sql</b> — <code>promo_codes</code>, каталогът (imartap)</summary>

```sql
-- =============================================================================
-- 06 — promo_codes (catalog / definition — the imartap master)
-- Target: imartap ONLY. Shared catalog across all sites (bg/ro/gr/al).
-- Run: mysql -D imartap < 06-create-imartap-promo_codes.sql
--
-- Plain SQL, no guards, no prepared statements. NOT idempotent: on a re-run or a
-- non-empty target MySQL raises an error and aborts — that error is the signal.
-- Baseline: a DB with NOTHING promo-related (original pre-migration schema).
-- An imartap that ALREADY has promo_codes is not a fresh target — this file will
-- fail with ERROR 1050 there, by design. Reconcile such a DB by hand.
--
-- Why this is a SEPARATE imartap file (like 07/order_promo_codes):
--   promo_codes is the single source of truth for every promo definition and
--   lives ONLY in imartap — the regional cart/order copies (01/02) store a
--   promo_code_id that points here (no cross-DB FK). It is the id master that
--   07's FK (fk_opc_promo_code_id) references, so it MUST be created BEFORE 07.
--
-- From-0 note: the live regional deploy assumes imartap already has this table
--   (shared catalog, out of scope). A true from-scratch deploy has no imartap
--   catalog yet — hence this file. Definition mirrors the live imartap table.
-- =============================================================================

CREATE TABLE `promo_codes` (
  `id`              INT           NOT NULL AUTO_INCREMENT,
  `code`            VARCHAR(50)   NOT NULL,
  `type`            ENUM('percent','fixed','shipping','shipping_percent') NOT NULL DEFAULT 'percent',
  `subtype`         ENUM('voucher','coupon') NULL DEFAULT NULL COMMENT 'fixed only: NULL/voucher → SKU 5555555, coupon → SKU 7777777',
  `discount_value`  DECIMAL(10,2) NOT NULL,
  `currency`        ENUM('BGN','EUR','ALL','RON') NOT NULL DEFAULT 'BGN' COMMENT 'code currency (ALL = Albanian lek, RON = Romanian leu)',
  `min_subtotal`    DECIMAL(10,2) NOT NULL DEFAULT 0,
  `shipping_cap`    DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'shipping/shipping_percent: max discount, NULL = uncapped',
  `max_uses`        INT           NOT NULL DEFAULT 0 COMMENT '0 = unlimited',
  `times_used`      INT           NOT NULL DEFAULT 0,
  `active`          BOOLEAN       NOT NULL DEFAULT TRUE,
  `stack_group`     TINYINT       NULL DEFAULT NULL COMMENT 'NULL = stacks freely, same number = only 1 from group',
  `expiration_date` VARCHAR(14)   NULL DEFAULT NULL COMMENT 'YYYYMMDDHHmmss, NULL = no expiry',
  `created_at`      VARCHAR(14)   NOT NULL,
  `used_at`         VARCHAR(14)   NULL DEFAULT NULL,
  `source`          ENUM('the-marketer','manual','bulk-import') NOT NULL DEFAULT 'manual',
  `note`            VARCHAR(255)  NULL DEFAULT NULL,
  -- 'all' is the WILDCARD (valid on every region), in live use by the staff
  -- codes (created_by 'Служебен ALL-…'). Do NOT confuse it with 'al' = Albania.
  -- Omitting 'all' here truncates those rows on a live imartap.
  `site`            ENUM('bg','ro','gr','al','all') NOT NULL COMMENT 'bg | ro | gr | al | all = всички региони',
  `created_by`      VARCHAR(255)  NULL DEFAULT NULL,

  PRIMARY KEY (`id`),
  UNIQUE KEY `code` (`code`),
  KEY `idx_active_exp` (`active`, `expiration_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

</details>

<details>
<summary><b>07-create-imartap-order_promo_codes.sql</b> — <code>order_promo_codes</code> <b>с</b> FK (imartap)</summary>

```sql
-- =============================================================================
-- 07 — order_promo_codes (imartap copy — the id master)
-- Target: imartap ONLY. Companion to 02 (regional copy).
-- Run: mysql -D imartap < 07-create-imartap-order_promo_codes.sql
--
-- Plain SQL, no guards, no prepared statements. NOT idempotent: on a re-run or a
-- non-empty target MySQL raises an error and aborts — that error is the signal.
-- Baseline: a DB with NOTHING promo-related (original pre-migration schema).
-- For an already-migrated DB whose order_promo_codes exists WITHOUT the FKs, use
-- the guarded ../../deploy/04-order_promo_codes-porachki-fk.sql instead.
--
-- Why a SEPARATE imartap file (the ONE difference vs the regional 02):
--   PromoCode::finalize() writes imartap FIRST (autoincrement master), reads the
--   id back, then mirrors it to the regional copy (lib/PromoCode.php:304-333).
--   Both referenced masters live in imartap — porachki (order) and promo_codes
--   (catalog) — so the referential links are enforced HERE with real FKs.
--   On the regional DB (02) order_id / promo_code_id are copies of imartap ids →
--   NO FK there. Same table, imartap-only foreign keys.
--
-- Prerequisite: `promo_codes` (created by 06, run it first) and `porachki` (order
-- master, from the core schema) both exist in imartap. FK add fails if imartap has
-- orphan history rows (order_id absent from porachki) — a fresh install is empty,
-- so this is clean.
-- =============================================================================

CREATE TABLE `order_promo_codes` (
  `id`                 INT           NOT NULL AUTO_INCREMENT,
  `order_id`           INT           NOT NULL COMMENT 'porachki.porachki_id',
  `promo_code_id`      INT           NOT NULL COMMENT 'promo_codes.id',
  `klienti_id`         INT           NOT NULL DEFAULT '0' COMMENT '0 = guest',
  `discount_applied`   DECIMAL(10,2) NOT NULL,
  `currency`           ENUM('BGN','EUR','ALL','RON') NOT NULL DEFAULT 'BGN' COMMENT 'snapshot of promo_codes.currency at order-finalize',
  `used_by_employeeId` INT           DEFAULT NULL COMMENT 'admin/backoffice app — storefront leaves NULL',
  `created_at`         VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_order_promo` (`order_id`,`promo_code_id`),
  KEY `idx_klienti` (`klienti_id`,`promo_code_id`),
  KEY `idx_promo_code` (`promo_code_id`),

  CONSTRAINT `fk_opc_order_id`
    FOREIGN KEY (`order_id`)      REFERENCES `porachki` (`porachki_id`)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_opc_promo_code_id`
    FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`)
    ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

</details>

<details>
<summary><b>08-seed-imartap-promo_codes.sql</b> — 7 example кода, по един на тип (опционален)</summary>

```sql
-- =============================================================================
-- 08 — promo_codes seed (one reference row per promo TYPE)
-- Target: imartap ONLY. promo_codes is the shared catalog (see 06).
-- Run: mysql -D imartap < 08-seed-imartap-promo_codes.sql   (AFTER 06)
--
-- Plain SQL, no guards. Baseline: a DB with NOTHING promo-related. `promo_codes.code`
-- is UNIQUE, so a re-run (or a collision with an operator-created code of the same
-- name) fails with ERROR 1062 instead of silently duplicating — that error is the
-- signal. Nothing here ever overwrites an existing row.
--
-- One example code for every distinct promo behaviour the storefront supports.
-- These are ACTIVE, working codes (so a fresh install can be QA'd end-to-end).
-- To ship a catalog WITHOUT live sample codes: set `active` = 0 below, or delete
-- them after verification (see Reset at the bottom of README.md).
--
-- Type → behaviour → catalog SKU (05 seed) → PromoCalc path (lib/PromoCalc.php):
--   percent           % off subtotal, best-only          SKU 8888888   (discount_value = %)
--   fixed / voucher   flat amount, burned on use         SKU 5555555   (discount_value = amount)
--   fixed / coupon    flat amount, burned on use         SKU 7777777   (discount_value = amount)
--   shipping (full)   whole shipping free, cap NULL      SKU 6666666   (discount_value unused → 0)
--   shipping (capped) up to shipping_cap off shipping    SKU 6666666   (discount_value unused → 0)
--   shipping_percent  % of full shipping, optional cap   —             (discount_value = %)
--
-- Catalog money-fields are authored in the code's own `currency`; lib/PromoCode.php
-- converts them to the BGN cart at read time via currency_rates (EUR ×1.95583 fixed;
-- BGN passthrough; ALL/lek ×manual rate). Set `currency` per code to 'BGN', 'EUR'
-- or 'ALL'. Codes 1-6 below are EUR examples (site = 'al', Albania); code 7 is an
-- 'ALL' (Albanian lek) example for lek testing. discount_value is monetary only for
-- `fixed`; percent / shipping_percent hold a %, which is never converted.
-- =============================================================================

SET NAMES utf8mb4;

--   1) PERCENT10     percent           — 10% off the cart subtotal (highest-percent-wins)
--   2) VOUCHER5      fixed / voucher   — 5.00 flat off subtotal (SKU 5555555)
--   3) COUPON5       fixed / coupon    — 5.00 flat off subtotal (SKU 7777777)
--   4) FREESHIP      shipping          — whole shipping free, uncapped (SKU 6666666)
--   5) SHIPCAP3      shipping          — up to 3.00 off shipping (SKU 6666666)
--   6) SHIPPCT50     shipping_percent  — 50% of full shipping, uncapped
--   7) VOUCHER500ALL fixed / voucher   — 500 lek off subtotal (SKU 5555555); priced in
--                                        lek → converts to BGN via currency_rates['ALL']
--                                        (500 * 0.0196 ≈ 9.80 BGN)
INSERT INTO `promo_codes`
  (`code`, `type`, `subtype`, `discount_value`, `currency`, `min_subtotal`, `shipping_cap`, `max_uses`, `active`, `expiration_date`, `created_at`, `source`, `note`, `site`, `created_by`) VALUES
  ('PERCENT10',     'percent',          NULL,      10.00, 'EUR', 0.00, NULL, 0, 1, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'Example: 10% off cart subtotal (SKU 8888888)',   'al', 'fresh-seed'),
  ('VOUCHER5',      'fixed',            'voucher',  5.00, 'EUR', 0.00, NULL, 0, 1, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'Example: 5.00 fixed voucher (SKU 5555555)',      'al', 'fresh-seed'),
  ('COUPON5',       'fixed',            'coupon',   5.00, 'EUR', 0.00, NULL, 0, 1, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'Example: 5.00 fixed coupon (SKU 7777777)',       'al', 'fresh-seed'),
  ('FREESHIP',      'shipping',         NULL,       0.00, 'EUR', 0.00, NULL, 0, 1, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'Example: free shipping, uncapped (SKU 6666666)', 'al', 'fresh-seed'),
  ('SHIPCAP3',      'shipping',         NULL,       0.00, 'EUR', 0.00, 3.00, 0, 1, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'Example: up to 3.00 off shipping (SKU 6666666)', 'al', 'fresh-seed'),
  ('SHIPPCT50',     'shipping_percent', NULL,      50.00, 'EUR', 0.00, NULL, 0, 1, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'Example: 50% off shipping, uncapped',            'al', 'fresh-seed'),
  ('VOUCHER500ALL', 'fixed',            'voucher', 500.00, 'ALL', 0.00, NULL, 0, 1, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'Example: 500 lek fixed voucher (SKU 5555555)',  'al', 'fresh-seed');
```

</details>

<details>
<summary><b>09-create-imartap-currency_rates.sql</b> — <code>currency_rates</code> + 4 реда (imartap)</summary>

```sql
-- =============================================================================
-- 09 — currency_rates (FX rate table — the imartap master)
-- Target: imartap ONLY. Shared across all sites (bg/ro/gr/al).
-- Run: mysql -D imartap < 09-create-imartap-currency_rates.sql
--
-- Plain SQL, no guards, no prepared statements. NOT idempotent: on a re-run or a
-- non-empty target MySQL raises an error and aborts — that error is the signal.
-- Baseline: a DB with NOTHING promo-related (original pre-migration schema).
-- The seed INSERT is a single statement: `currency` is the PRIMARY KEY, so a
-- re-run fails with ERROR 1062 rather than overwriting a live job-updated rate.
--
-- Purpose (issue #610): promo money-fields are authored in the code's own
-- `currency` (promo_codes.currency). The cart is always priced in BGN, so
-- lib/PromoCode.php converts EUR/RON/… → BGN at the catalog read boundary using
-- these rates (PromoCode::toBgn / ratesToBgn). Base currency = BGN.
--
--   rate_to_bgn : 1 unit of `currency` = rate_to_bgn BGN.
--   is_fixed=1  : legally fixed / irrevocable (BGN self, EUR adoption rate).
--                 The rate-updater (scripts/update-currency-rates.php) MUST skip
--                 these — only is_fixed=0 (floating) rows are refreshed from BNB.
--
-- NOTE: `promo_codes.currency` (file 06) already ships ENUM('BGN','EUR','ALL','RON'),
-- so every currency seeded below is authorable on a code without a further
-- migration. Adding a NEW currency means extending that ENUM first, then a row here.
-- =============================================================================

CREATE TABLE `currency_rates` (
  `currency`    CHAR(3)        NOT NULL                COMMENT 'ISO 4217: BGN (base), EUR, RON, ...',
  `rate_to_bgn` DECIMAL(18,8)  NOT NULL                COMMENT '1 unit of `currency` = rate_to_bgn BGN',
  `is_fixed`    TINYINT(1)     NOT NULL DEFAULT 0      COMMENT '1 = legally fixed (irrevocable) — updater MUST skip',
  `source`      VARCHAR(16)    NOT NULL DEFAULT 'manual' COMMENT 'fixed | bnb | manual',
  `updated_at`  DATETIME       NULL     DEFAULT NULL   COMMENT 'last refresh, NULL until first job run',
  PRIMARY KEY (`currency`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--   BGN — base currency (self). Fixed.
--   EUR — irrevocable BGN adoption rate 1 EUR = 1.95583 BGN. Fixed, never fetched.
--   RON — floating (Romania). Placeholder ~ recent value; refreshed by the BNB job.
--   ALL — Albanian lek. Floating, but BNB does NOT publish it → source 'manual';
--         the BNB job leaves it untouched. Placeholder ~ 1 lek; update by hand or
--         point the fetch at a provider that carries lek (e.g. Bank of Albania).
INSERT INTO `currency_rates` (`currency`, `rate_to_bgn`, `is_fixed`, `source`, `updated_at`) VALUES
  ('BGN', 1.00000000, 1, 'fixed',  NULL),
  ('EUR', 1.95583000, 1, 'fixed',  NULL),
  ('RON', 0.39350000, 0, 'bnb',    NULL),
  ('ALL', 0.01960000, 0, 'manual', NULL);
```

</details>

<details>
<summary><b>10-verify.sql</b> — read-only, какво реално е кацнало (регионална + imartap)</summary>

```sql
-- =============================================================================
-- 10 — POST-RUN VERIFICATION (read-only, writes NOTHING)
-- Target: EVERY DB you migrated — regional AND imartap.
-- Run: mysql -D <db> --table < 10-verify.sql
--
-- Counterpart to 00-preflight.sql. Because the migration files are plain,
-- unguarded SQL, a failed statement leaves the file half-applied — this proves
-- what actually landed. Run it on each DB after its last migration file.
--
-- Expected per target (checks that do not apply return "n/a"):
--   regional : cart_promo_codes + order_promo_codes tables
--              item / item_l / item_no  → 5 promo columns each
--              porachki → pordost_coupon_discount
--              porachki_l / porachki_no → + promo_fixed_discount
--              catalog → exactly 4 promo SKUs, vidimost=0, p_acti=0
--   imartap  : promo_codes + order_promo_codes + currency_rates tables
--              order_promo_codes → 2 FKs (porachki, promo_codes)
--              item → 5 promo columns; porachki → pordost_coupon_discount
--              currency_rates → 4 rows; promo_codes → 7 fresh-seed rows
-- =============================================================================

SELECT DATABASE() AS `db`, NOW() AS `verified_at`;


-- ── A. Promo tables that landed here ────────────────────────────────────────
SELECT
  'A. promo tables' AS `check`,
  TABLE_NAME        AS `table`,
  ENGINE,
  TABLE_COLLATION   AS `collation`,
  TABLE_ROWS        AS `approx_rows`
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('promo_codes','cart_promo_codes','order_promo_codes','currency_rates')
ORDER BY TABLE_NAME;


-- ── B. item* promo columns — expect 5 per existing item table ───────────────
--    discount_applied, it_cena_new, it_suma_new, item_br_new, promot_new
SELECT
  'B. item promo columns' AS `check`,
  TABLE_NAME              AS `table`,
  COUNT(*)                AS `found`,
  IF(COUNT(*) = 5, 'OK', 'FAIL — expected 5') AS `result`,
  GROUP_CONCAT(COLUMN_NAME ORDER BY COLUMN_NAME SEPARATOR ', ') AS `columns`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('item','item_l','item_no')
  AND COLUMN_NAME IN ('discount_applied','it_cena_new','it_suma_new','item_br_new','promot_new')
GROUP BY TABLE_NAME
ORDER BY TABLE_NAME;


-- ── C. it_cena / it_suma still the ORIGINAL stored columns ──────────────────
-- The whole point of the fresh path: nothing was virtualised or renamed. EXTRA
-- must be empty on every row.
SELECT
  'C. it_cena/it_suma untouched' AS `check`,
  TABLE_NAME    AS `table`,
  COLUMN_NAME   AS `column`,
  COLUMN_TYPE   AS `type`,
  IF(EXTRA LIKE '%GENERATED%', CONCAT('FAIL — ', EXTRA), 'OK — stored') AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('item','item_l','item_no')
  AND COLUMN_NAME IN ('it_cena','it_suma')
ORDER BY TABLE_NAME, COLUMN_NAME;


-- ── D. porachki* promo columns ──────────────────────────────────────────────
-- porachki → 1 (pordost_coupon_discount); porachki_l / porachki_no → 2.
SELECT
  'D. porachki promo columns' AS `check`,
  TABLE_NAME                  AS `table`,
  COUNT(*)                    AS `found`,
  IF(COUNT(*) = IF(TABLE_NAME = 'porachki', 1, 2), 'OK', 'FAIL') AS `result`,
  GROUP_CONCAT(COLUMN_NAME ORDER BY COLUMN_NAME SEPARATOR ', ') AS `columns`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('porachki','porachki_l','porachki_no')
  AND COLUMN_NAME IN ('pordost_coupon_discount','promo_fixed_discount')
GROUP BY TABLE_NAME
ORDER BY TABLE_NAME;


-- ── E. currency ENUMs carry all four currencies ─────────────────────────────
-- promo_codes / cart_promo_codes / order_promo_codes must all read
-- enum('BGN','EUR','ALL','RON'). A short ENUM truncates non-BGN codes on write.
SELECT
  'E. currency ENUM' AS `check`,
  TABLE_NAME         AS `table`,
  COLUMN_TYPE        AS `enum`,
  IF(COLUMN_TYPE LIKE '%BGN%' AND COLUMN_TYPE LIKE '%EUR%'
     AND COLUMN_TYPE LIKE '%ALL%' AND COLUMN_TYPE LIKE '%RON%',
     'OK', 'FAIL — missing a currency') AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND COLUMN_NAME = 'currency'
  AND TABLE_NAME IN ('promo_codes','cart_promo_codes','order_promo_codes')
ORDER BY TABLE_NAME;


-- ── F. promo_codes.site ENUM must include the 'all' wildcard ────────────────
-- 'all' = every region (staff codes). NOT the same as 'al' = Albania.
-- 06 ships ENUM('bg','ro','gr','al','all'). Note some older DBs (dev imartap)
-- carry `site` as VARCHAR instead — that stores 'all' fine but enforces nothing,
-- so a typo'd region is silently accepted. Flagged separately below.
SELECT
  'F. site ENUM has wildcard' AS `check`,
  DATA_TYPE                   AS `data_type`,
  COLUMN_TYPE                 AS `declared_as`,
  CASE
    WHEN DATA_TYPE <> 'enum'            THEN CONCAT('WARN — not an ENUM, no region enforced: ', COLUMN_TYPE)
    WHEN COLUMN_TYPE LIKE '%\'all\'%'   THEN 'OK'
    ELSE 'FAIL — ENUM lacks the all wildcard, staff codes truncate on write'
  END AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'promo_codes' AND COLUMN_NAME = 'site';


-- ── G. imartap order_promo_codes foreign keys — expect exactly 2 ────────────
-- fk_opc_order_id → porachki.porachki_id, fk_opc_promo_code_id → promo_codes.id.
-- On a regional DB this is correctly EMPTY (the ids are imartap copies, no FK).
SELECT
  'G. order_promo_codes FKs' AS `check`,
  k.CONSTRAINT_NAME          AS `constraint`,
  k.COLUMN_NAME              AS `column`,
  CONCAT(k.REFERENCED_TABLE_NAME, '.', k.REFERENCED_COLUMN_NAME) AS `references`
FROM information_schema.KEY_COLUMN_USAGE k
WHERE k.TABLE_SCHEMA = DATABASE()
  AND k.TABLE_NAME = 'order_promo_codes'
  AND k.REFERENCED_TABLE_NAME IS NOT NULL
ORDER BY k.CONSTRAINT_NAME;


-- =============================================================================
-- Everything ABOVE reads information_schema only → runs on ANY target, no errors.
-- Everything BELOW reads the seeded tables themselves, so each block only works on
-- the target that owns that table. On the other target it raises ERROR 1146
-- (Table doesn't exist), which aborts the rest of the file.
--
-- Nothing here writes, so the simplest way to see all of it is:
--     mysql -D <db> --table --force < 10-verify.sql
-- `--force` continues past the expected 1146s. NEVER use --force on the migration
-- files 01-09 — there a stopped run is the whole point.
-- =============================================================================


-- ── H. currency_rates seed — expect 4 rows ───────────────────── IMARTAP ONLY ─
-- BGN/EUR is_fixed=1 (updater must skip); RON/ALL is_fixed=0 (floating).
SELECT 'H. currency_rates' AS `check`,
       `currency`, `rate_to_bgn`, `is_fixed`, `source`, `updated_at`
FROM `currency_rates`
ORDER BY `is_fixed` DESC, `currency`;


-- ── I. promo_codes seed — expect 7 rows, one per behaviour ───── IMARTAP ONLY ─
SELECT 'I. promo_codes seed' AS `check`,
       `id`, `code`, `type`, `subtype`, `discount_value`, `currency`,
       `shipping_cap`, `active`, `site`
FROM `promo_codes`
WHERE `created_by` = 'fresh-seed'
ORDER BY `id`;


-- ── J. catalog promo SKUs — expect EXACTLY 4 rows ───────────── REGIONAL ONLY ─
-- More than 4 = 05 ran twice (no UNIQUE KEY on cat_no). vidimost/p_acti must be 0
-- or a shopper could add the promo SKU to a cart by hand.
SELECT 'J. catalog promo SKUs' AS `check`,
       `cat_no`, `ime`, `miarka`, `cena`, `vidimost`, `p_acti`,
       IF(`vidimost` = 0 AND `p_acti` = 0, 'OK', 'FAIL — must be hidden/inactive') AS `result`
FROM `catalog`
WHERE `cat_no` IN ('5555555','6666666','7777777','8888888')
ORDER BY `cat_no`;
```

</details>

### Ако гръмне

Гол SQL спира на проблемния statement и **оставя предходните приложени**. Пусни `10-verify.sql` да видиш какво е кацнало, довърши ръчно или reset (виж README).

|     |     |
| --- | --- |
| Грешка | Значение |
| `ERROR 1050 Table 'X' already exists` | 01/02/06/07/09 вече са минали |
| `ERROR 1060 Duplicate column name 'X'` | 03/04 вече са минали за тази таблица |
| `ERROR 1146 Table 'X' doesn't exist` | Грешен target (напр. 01 срещу imartap) |
| `ERROR 1062 Duplicate entry` | 08/09 seed вече е минал |
| `ERROR 1215 Cannot add foreign key` | 07 преди 06, или липсва `porachki` в imartap |

### ⚠️ Единственият файл без защита — 05

`catalog` няма UNIQUE KEY на `cat_no` → повторно пускане на 05 **не гърми**, вкарва 4 дублирани реда тихо. Пусни го точно веднъж. Ако стане:

```sql
DELETE FROM `catalog` WHERE `cat_no` IN ('5555555','6666666','7777777','8888888');
-- после 05 наново
```

### Очаквано от `10-verify.sql`

- регионална: `cart_promo_codes` + `order_promo_codes`; 5 промо колони на всяка `item*`; `porachki` 1 колона, `porachki_l`/`_no` по 2; 4 catalog SKU с `vidimost=0, p_acti=0`
- imartap: `promo_codes` + `order_promo_codes` (2 FK) + `currency_rates` (4 реда); 7 кода `created_by='fresh-seed'`
- `it_cena`/`it_suma` навсякъде да са **stored** (`EXTRA` празно) — не generated