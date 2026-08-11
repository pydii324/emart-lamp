-- =============================================================================
-- 07 — POST-RUN VERIFICATION (read-only, writes NOTHING)
-- Target: EVERY DB you changed — imartap AND every regional DB.
-- Run: mysql -D <db> --table --force < 07-verify.sql
--
-- Counterpart to 00-preflight.sql. The migration files are plain, unguarded SQL,
-- so a failed statement leaves the file half-applied — this proves what actually
-- landed. Run it on each DB after its last migration file.
--
-- Expected per target:
--   imartap  : promo_codes.site → 37 values, NULLable, no 'all'
--              promo_codes.currency / order_promo_codes.currency → 18 values
--              currency_rates → rate_to_eur, EUR 1.0 fixed, BGN 0.51129188 fixed
--              currency_rates → 18 rows, every authorable currency covered
--   regional : cart_promo_codes.currency / order_promo_codes.currency → 18 values
--
-- Checks A–B read information_schema only and run on ANY target. C–G read the
-- promo tables themselves and are imartap-only; on a regional DB they raise
-- ERROR 1146, which is why this file wants --force. Nothing here writes.
-- NEVER use --force on the migration files 01-06.
-- =============================================================================

SELECT DATABASE() AS `db`, NOW() AS `verified_at`;


-- ── A. ENUM widths — expect 37 regions / 18 currencies ──────────────────────
-- Counting the commas asserts the width without pasting the whole list.
SELECT
  'A. enum width' AS `check`,
  TABLE_NAME      AS `table`,
  COLUMN_NAME     AS `column`,
  (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 AS `values`,
  COLUMN_DEFAULT  AS `default`,
  IS_NULLABLE     AS `nullable`,
  CASE
    WHEN DATA_TYPE <> 'enum'                                   THEN CONCAT('FAIL — not an ENUM: ', COLUMN_TYPE)
    WHEN COLUMN_NAME = 'site' AND COLUMN_TYPE LIKE '%\'all\'%' THEN 'FAIL — retired wildcard still declared'
    WHEN COLUMN_NAME = 'site'
         AND (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 <> 37
      THEN 'FAIL — region list out of sync with PromoCode::SITES (04 not run?)'
    WHEN COLUMN_NAME = 'currency'
         AND (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 <> 18
      THEN 'FAIL — missing a currency (04/05/06 not run on this table?)'
    WHEN COLUMN_NAME = 'currency' AND COLUMN_DEFAULT <> 'EUR'
      THEN 'FAIL — DEFAULT still on the old base currency'
    ELSE 'OK'
  END AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND ((TABLE_NAME = 'promo_codes' AND COLUMN_NAME IN ('site','currency'))
    OR (TABLE_NAME IN ('cart_promo_codes','order_promo_codes') AND COLUMN_NAME = 'currency'))
ORDER BY TABLE_NAME, COLUMN_NAME;


-- ── B. the original four values kept their positions ────────────────────────
-- A drift check, not a data-integrity one: rows are safe either way (MySQL
-- converts an ENUM by the value's string), but a WARN means this instance's
-- declaration diverges from every other one — COLUMN_TYPE comparisons stop being
-- meaningful and the next ALTER on the column pays for a full table copy.
SELECT
  'B. original values first' AS `check`,
  TABLE_NAME                 AS `table`,
  COLUMN_NAME                AS `column`,
  LEFT(COLUMN_TYPE, 40)      AS `starts_with`,
  IF(COLUMN_TYPE LIKE
       IF(COLUMN_NAME = 'site', 'enum(\'bg\',\'ro\',\'gr\',\'al\',%', 'enum(\'BGN\',\'EUR\',\'ALL\',\'RON\',%'),
     'OK', 'WARN — declaration order drifted from every other instance') AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND ((TABLE_NAME = 'promo_codes' AND COLUMN_NAME IN ('site','currency'))
    OR (TABLE_NAME IN ('cart_promo_codes','order_promo_codes') AND COLUMN_NAME = 'currency'))
ORDER BY TABLE_NAME, COLUMN_NAME;


-- =============================================================================
-- Everything BELOW reads promo_codes / currency_rates directly → IMARTAP ONLY.
-- On a regional DB each raises ERROR 1146 and aborts the rest of the file.
-- =============================================================================


-- ── C. nothing was truncated to the empty string ────────────────── [imartap] ─
-- Expect 0. Any row here means 04 ran without 03 and values were lost.
SELECT
  'C. truncated to empty' AS `check`,
  COUNT(*)                AS `rows`,
  IF(COUNT(*) = 0, 'OK', 'FAIL — 03 was skipped before 04, values were lost') AS `result`
FROM `promo_codes`
WHERE `site` = '' OR `currency` = '';


-- ── D. region distribution, parked rows included ────────────────── [imartap] ─
-- Every NULL row must be inactive; an active NULL means a live code lost its
-- region. The alias is `region`, not `site` — GROUP BY `site` would otherwise be
-- ambiguous between the alias and the column and MySQL warns (1052) every run.
SELECT
  'D. site values in use'             AS `check`,
  COALESCE(`site`, '(NULL — parked)') AS `region`,
  `active`,
  COUNT(*)                            AS `rows`,
  CASE
    WHEN `site` IS NOT NULL THEN 'OK'
    WHEN `active` = 0       THEN 'parked — unredeemable by design, kept for audit'
    ELSE 'FAIL — active code with no region, it can never be redeemed'
  END AS `result`
FROM `promo_codes`
GROUP BY `site`, `active`
ORDER BY `rows` DESC;


-- ── E. currency_rates is EUR-based, 18 rows ─────────────────────── [imartap] ─
-- rate_to_eur = how many EUR one unit of the currency buys. An instance still
-- showing `rate_to_bgn` errors here with ERROR 1054 and wants file 01.
SELECT 'E. currency_rates' AS `check`,
       `currency`, `rate_to_eur`, `is_fixed`, `source`, `updated_at`
FROM `currency_rates`
ORDER BY `is_fixed` DESC, `currency`;


-- ── E2. the two fixed anchors are exact ─────────────────────────── [imartap] ─
-- If EUR is anything but 1.00000000 every converted amount is scaled by that
-- factor. BGN must be the irrevocable 1/1.95583 and flagged fixed, or the nightly
-- BNB job keeps trying to fetch a currency its EUR-based feed no longer lists.
SELECT
  'E2. fixed anchors' AS `check`,
  `currency`,
  `rate_to_eur`,
  `is_fixed`,
  `source`,
  CASE
    WHEN `currency` = 'EUR' AND `rate_to_eur` = 1.00000000 AND `is_fixed` = 1 AND `source` = 'fixed' THEN 'OK'
    WHEN `currency` = 'BGN' AND `rate_to_eur` = 0.51129188 AND `is_fixed` = 1 AND `source` = 'fixed' THEN 'OK'
    ELSE 'FAIL — anchor rate, is_fixed or source is wrong (01 not run / half-run?)'
  END AS `result`
FROM `currency_rates`
WHERE `currency` IN ('EUR','BGN')
ORDER BY `currency`;


-- ── E3. magnitudes are EUR-scale, not leva-scale ────────────────── [imartap] ─
-- Every rate is now "EUR per 1 unit", so a currency weaker than the euro must be
-- < 1 and GBP must be > 1. A row still ~1.95× its expected value means file 01
-- step 2 did not run.
SELECT
  'E3. magnitudes' AS `check`,
  `currency`,
  `rate_to_eur`,
  CASE
    WHEN `currency` = 'GBP' AND `rate_to_eur` BETWEEN 0.8 AND 2.0 THEN 'OK'
    WHEN `currency` = 'GBP'                                       THEN 'FAIL — GBP out of range, still leva-based?'
    WHEN `rate_to_eur` >= 1.5                                     THEN 'WARN — suspiciously large for a EUR-based rate'
    ELSE 'OK'
  END AS `result`
FROM `currency_rates`
ORDER BY `rate_to_eur` DESC;


-- ── F. nothing the BNB job owns is flagged fixed, and vice versa ── [imartap] ─
-- Expect only EUR/BGN fixed, both with source 'fixed'.
SELECT
  'F. fixed vs fetchable' AS `check`,
  `is_fixed`,
  `source`,
  COUNT(*)                AS `rows`,
  GROUP_CONCAT(`currency` ORDER BY `currency` SEPARATOR ', ') AS `currencies`,
  CASE
    WHEN `is_fixed` = 1 AND `source` <> 'fixed' THEN 'FAIL — fixed row not marked source=fixed'
    WHEN `is_fixed` = 0 AND `source`  = 'fixed' THEN 'FAIL — source=fixed but the job may overwrite it'
    ELSE 'OK'
  END AS `result`
FROM `currency_rates`
GROUP BY `is_fixed`, `source`
ORDER BY `is_fixed` DESC, `source`;


-- ── G. every authorable currency has a rate row ─────────────────── [imartap] ─
-- PromoCode::toEur() falls back to rate 1.0 for a currency with no row, i.e. it
-- treats the amount as already-EUR: a `fixed` HUF code would deduct its face
-- value in euro. Expect 0 rows.
SELECT
  'G. currency without a rate' AS `check`,
  p.`currency`,
  COUNT(*)                     AS `codes`,
  'FAIL — add a currency_rates row before authoring in this currency' AS `result`
FROM `promo_codes` p
WHERE NOT EXISTS (SELECT 1 FROM `currency_rates` r WHERE r.`currency` = p.`currency`)
GROUP BY p.`currency`;
