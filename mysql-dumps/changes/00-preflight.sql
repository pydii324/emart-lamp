-- =============================================================================
-- 00 — PRE-FLIGHT (read-only, writes NOTHING)
-- Target: EVERY DB you are about to change — imartap AND every regional DB.
-- Run: mysql -D <db> --table --force < 00-preflight.sql
--
-- The rest of this set is plain, unguarded SQL: the first bad statement aborts
-- the file and leaves the earlier statements applied. This file proves up-front
-- that the target really is on the OLD promo schema, so that never happens.
--
-- EXPECTED STARTING STATE (what this set migrates FROM):
--   promo_codes.site      VARCHAR(10)  or  ENUM('bg','ro','gr','al')
--   promo_codes.currency  ENUM('BGN','EUR','ALL','RON') NOT NULL DEFAULT 'BGN'
--   cart_promo_codes.currency  / order_promo_codes.currency  — the same 4 values
--   currency_rates.rate_to_bgn  DECIMAL(18,8)   (BGN is the conversion base)
--
-- END STATE (what the current storefront PHP expects):
--   promo_codes.site      ENUM(37 regions) NULL     — see PromoCode::SITES
--   *.currency            ENUM(18 currencies) NOT NULL DEFAULT 'EUR'
--   currency_rates.rate_to_eur DECIMAL(18,8)  (EUR is the conversion base)
--
-- If a check below reports FAIL, this DB is NOT on the expected baseline. Do not
-- continue — read README.md §"Ако базата не е на очаквания baseline".
--
-- Checks A–F read information_schema only and run on ANY target: a table that
-- does not exist here is simply a missing row, not an error. Checks G–I read the
-- promo tables themselves and are imartap-only; on a regional DB they raise
-- ERROR 1146, which is why this file wants --force. Nothing here writes.
-- =============================================================================

SELECT DATABASE() AS `db`, VERSION() AS `mysql_version`, NOW() AS `checked_at`;


-- ── A. Which target am I on? ─────────────────────────────────────────────────
-- imartap expects: promo_codes, order_promo_codes, currency_rates.
-- A regional DB expects: cart_promo_codes, order_promo_codes (no promo_codes,
-- no currency_rates — those live in imartap alone).
SELECT
  'A. promo tables present' AS `check`,
  TABLE_NAME                AS `table`,
  TABLE_ROWS                AS `approx_rows`
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('promo_codes','cart_promo_codes','order_promo_codes','currency_rates')
ORDER BY TABLE_NAME;


-- ── B. currency_rates is still BGN-based ────────────────────────── [imartap] ─
-- rate_to_bgn present → not re-based yet, file 01 applies.
-- rate_to_eur present → file 01 already ran here; skip it (it would ERROR 1054).
SELECT
  'B. rate column'  AS `check`,
  COLUMN_NAME       AS `column`,
  COLUMN_TYPE       AS `type`,
  CASE COLUMN_NAME
    WHEN 'rate_to_bgn' THEN 'OK — on the old base, run 01'
    ELSE 'ALREADY DONE — 01 has run here, skip it'
  END AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME  = 'currency_rates'
  AND COLUMN_NAME IN ('rate_to_bgn','rate_to_eur');


-- ── C. promo_codes.site — the column file 04 widens ─────────────── [imartap] ─
-- Both VARCHAR(10) and the four-region ENUM are valid baselines. A 37-value ENUM
-- means 04 has already run.
SELECT
  'C. site column'  AS `check`,
  DATA_TYPE         AS `data_type`,
  IS_NULLABLE       AS `nullable`,
  (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 AS `values`,
  COLUMN_TYPE       AS `declared_as`,
  CASE
    WHEN DATA_TYPE <> 'enum' THEN 'OK — VARCHAR baseline, nothing enforced yet'
    WHEN (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 = 37
      THEN 'ALREADY DONE — 04 has run here'
    WHEN COLUMN_TYPE LIKE 'enum(\'bg\',\'ro\',\'gr\',\'al\')%'
      THEN 'OK — four-region ENUM baseline'
    ELSE 'FAIL — unexpected shape, reconcile by hand before running 04'
  END AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'promo_codes' AND COLUMN_NAME = 'site';


-- ── D. every `currency` ENUM in this DB ──────────────────────────────────────
-- Expect 4 values (BGN,EUR,ALL,RON) on each table that exists here. 18 means the
-- matching file (04 / 05 / 06) has already run.
SELECT
  'D. currency ENUM' AS `check`,
  TABLE_NAME         AS `table`,
  (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 AS `values`,
  COLUMN_DEFAULT     AS `default`,
  COLUMN_TYPE        AS `declared_as`,
  CASE
    WHEN DATA_TYPE <> 'enum' THEN CONCAT('FAIL — not an ENUM: ', COLUMN_TYPE)
    WHEN (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 = 18
      THEN 'ALREADY DONE — this table has been widened'
    WHEN (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 = 4
      THEN 'OK — four-currency baseline'
    ELSE 'FAIL — unexpected width, reconcile by hand'
  END AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND COLUMN_NAME = 'currency'
  AND TABLE_NAME IN ('promo_codes','cart_promo_codes','order_promo_codes')
ORDER BY TABLE_NAME;


-- ── E. the ENUMs are APPENDED to, never reordered ────────────────────────────
-- Files 04/05/06 keep bg,ro,gr,al and BGN,EUR,ALL,RON in their original first
-- four positions. This is about COST, not corruption: MySQL converts an ENUM
-- column by the value's STRING, so a differently-ordered source list still lands
-- on the right values — it just forces ALGORITHM=COPY (a full table rebuild)
-- where an append is in-place, and it makes this instance's COLUMN_TYPE differ
-- from every other one, which is what file 07 compares.
SELECT
  'E. original values first' AS `check`,
  TABLE_NAME                 AS `table`,
  COLUMN_NAME                AS `column`,
  LEFT(COLUMN_TYPE, 40)      AS `starts_with`,
  IF(DATA_TYPE <> 'enum', 'n/a (not an ENUM)',
     IF(COLUMN_TYPE LIKE
          IF(COLUMN_NAME = 'site', 'enum(\'bg\',\'ro\',\'gr\',\'al\'%', 'enum(\'BGN\',\'EUR\',\'ALL\',\'RON\'%'),
        'OK', 'WARN — order drifted; conversion is still value-safe but costs a table copy')) AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND ((TABLE_NAME = 'promo_codes' AND COLUMN_NAME IN ('site','currency'))
    OR (TABLE_NAME IN ('cart_promo_codes','order_promo_codes') AND COLUMN_NAME = 'currency'))
ORDER BY TABLE_NAME, COLUMN_NAME;


-- ── F. promo_codes unique key — INFORMATIONAL ───────────────────── [imartap] ─
-- The current schema wants UNIQUE (`code`,`site`); an older instance may still
-- carry UNIQUE (`code`) alone. Nothing in THIS set depends on it — file 03 parks
-- rows on NULL and a UNIQUE index tolerates any number of NULLs either way — but
-- while `code` is globally unique the same code string cannot exist in two
-- regions, which is the whole point of a 37-region catalog. Fix separately with
-- mysql-dumps/deploy/09-fix-promo-codes-code-site-unique.sql.
SELECT
  'F. promo_codes unique keys' AS `check`,
  INDEX_NAME                   AS `index`,
  GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX SEPARATOR ', ') AS `columns`,
  CASE INDEX_NAME
    WHEN 'uq_code_site' THEN 'OK — one code per region'
    WHEN 'PRIMARY'      THEN 'n/a — surrogate key'
    ELSE 'INFO — still one code globally; see deploy/09 (independent of this set)'
  END AS `result`
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'promo_codes'
  AND NON_UNIQUE = 0
GROUP BY INDEX_NAME
ORDER BY INDEX_NAME;


-- =============================================================================
-- Everything ABOVE reads information_schema only → runs on ANY target, no errors.
-- Everything BELOW reads promo_codes / currency_rates themselves and is
-- IMARTAP-ONLY. On a regional DB each raises ERROR 1146 (Table doesn't exist),
-- which aborts the rest of the file — hence --force on this file. Nothing here
-- writes either way. NEVER use --force on the migration files 01-06.
-- =============================================================================


-- ── G. rows file 03 will park on NULL ───────────────────────────── [imartap] ─
-- Anything listed has a `site` outside the new 37-region list: the retired 'all'
-- wildcard, a typo, an empty string, or already NULL. All of them are
-- unredeemable TODAY (lib/PromoCode.php matches the region exactly), so parking
-- them changes nothing functionally — it only makes the ENUM conversion lossless.
-- An ACTIVE row here is worth a look before you continue: it is a code someone
-- believes works and does not.
SELECT
  'G. rows to be parked on NULL' AS `check`,
  `site`                         AS `current_site`,
  `active`,
  COUNT(*)                       AS `rows`,
  GROUP_CONCAT(`code` ORDER BY `code` SEPARATOR ', ') AS `codes`
FROM `promo_codes`
WHERE `site` IS NULL
   OR `site` NOT IN ('bg','ro','gr','al',
                     'en','md','at','cz','de','es','hr','hu','it','pl','si','sk','cy','uk','us','co',
                     'be','dk','ee','fi','fr','lt','lv','nl','pt','se','mk','rs','ua','tr','ru',
                     'biz','org')
GROUP BY `site`, `active`
ORDER BY `active` DESC, `rows` DESC;


-- ── H. the rates as they stand, and what 01 turns them into ─────── [imartap] ─
-- Eyeball two: EUR must land on exactly 1.00000000 and BGN on 0.51129188.
-- Anything else means the table was not in leva to begin with — stop and read
-- README.md before running 01.
SELECT
  'H. before → after'               AS `check`,
  `currency`,
  `rate_to_bgn`                     AS `now_in_bgn`,
  ROUND(`rate_to_bgn` / 1.95583, 8) AS `becomes_in_eur`,
  `is_fixed`,
  `source`
FROM `currency_rates`
ORDER BY `is_fixed` DESC, `currency`;


-- ── I. currencies file 02 is about to insert ────────────────────── [imartap] ─
-- 02 is a plain INSERT and the whole statement is atomic: if ANY of these 14
-- already has a row, the insert fails with ERROR 1062 and NONE of them land.
-- Expect: Empty set. Any row returned = remove that literal from 02 before
-- running it (or delete the existing row if it is a stale placeholder).
SELECT 'I. new-currency rows already present' AS `check`,
       `currency`, `rate_to_bgn`, `is_fixed`, `source`, `updated_at`
FROM `currency_rates`
WHERE `currency` IN ('CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD',
                     'RUB','SEK','TRY','UAH','USD','CAD')
ORDER BY `currency`;
