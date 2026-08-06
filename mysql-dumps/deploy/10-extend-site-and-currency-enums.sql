-- =============================================================================
-- DEPLOY 10 — Extend promo_codes.site to 37 regions + currency to 17 currencies
-- =============================================================================
-- Run MANUALLY. Plain statements — no guards. Idempotent: a second run re-applies
-- the same column definitions (a no-op MODIFY), updates 0 rows in Section B and
-- inserts 0 rows in Section D.2 (INSERT IGNORE).
--
-- WHY:
--   fresh/06 used to ship `site` ENUM('bg','ro','gr','al'). The storefront list
--   grew to 37 regions, so fresh/06 now declares all of them and lib/PromoCode.php
--   ::SITES mirrors it. An instance that ALREADY ran the old fresh/06 (or that
--   still carries the pre-migration VARCHAR) needs this file to catch up — a
--   region outside the column's ENUM cannot be written at all, and one outside
--   PromoCode::SITES can never be redeemed.
--
--   Each new region also needs a currency: PromoCode::SITE_CURRENCY maps
--   cz→CZK, pl→PLN, uk→GBP, us→USD, … so `currency` grows from 4 values to 17
--   in every table that stores one, and currency_rates gains the matching rows.
--
-- WHERE TO RUN (two different targets — read the section headers):
--   • Sections A–D → imartap ONLY (promo_codes, currency_rates and imartap's own
--     order_promo_codes copy all live there).
--   • Section E    → EVERY regional DB (cart_promo_codes / order_promo_codes
--     pivots). Repeat it once per region.
--   • Section F    → verification, run on whichever DB you just touched.
--
-- ORDER vs the other deploy files:
--   Run AFTER deploy/08 (retires the `site = 'all'` wildcard) and AFTER deploy/09
--   (UNIQUE(code) → UNIQUE(code, site)). Section B relies on 08 having already
--   deactivated the wildcard rows, and parks them on NULL — which UNIQUE(code,
--   site) tolerates, because MySQL lets a UNIQUE index hold any number of NULLs.
--
-- TWO THINGS THIS FILE DELIBERATELY DOES:
--
--   1. It APPENDS to both ENUMs, never reorders them. An ENUM column stores an
--      ordinal, not the string, so 'bg','ro','gr','al' and 'BGN','EUR','ALL','RON'
--      MUST stay in their original positions — the 33 regions and 13 currencies
--      go after them. Appending keeps the ALTER cheap (MySQL 8 can do it
--      in-place) and leaves every existing row's value untouched. Reordering
--      would rewrite the table and silently remap rows to different regions.
--      → Run Section A first and eyeball the current COLUMN_TYPE. If some
--        instance has these four in a DIFFERENT order, STOP: fix that instance by
--        hand, do not run Section C against it.
--
--   2. It makes `site` NULLable, unlike fresh/06 which declares it NOT NULL.
--      That is on purpose and the two shapes are both correct:
--        • fresh/06 targets a virgin DB — no legacy rows, so NOT NULL is free.
--        • here there may be rows whose `site` is not a real region: the retired
--          'all' wildcard, or a typo'd value that the pre-migration VARCHAR(10)
--          accepted silently. Converting those to an ENUM that lacks the value
--          truncates them to '' (or errors under STRICT mode) — so Section B
--          parks them on NULL first, which needs a NULLable column.
--      NULL is the honest value: siteSql() emits `site IN ('bg')`-style SQL and
--      `IN` never matches NULL, and siteAllows() compares with === against a
--      string, so a NULL-site row is unredeemable in every region — exactly what
--      those rows already were. The old value is preserved in `note` for audit.
-- =============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- Section A — preflight (read-only, writes NOTHING)   [imartap]
-- ═══════════════════════════════════════════════════════════════════════════
-- A.1 — what the two columns look like right now. Expect one of:
--   `site`     : varchar(10) (pre-migration) | enum('bg','ro','gr','al')
--   `currency` : enum('BGN','EUR','ALL','RON')
-- If `site` is already the 37-value ENUM this file has run before — fine, it is
-- idempotent. If the first four values are in any other order, STOP (see header).
SELECT
  'A.1 current column types' AS `check`,
  COLUMN_NAME                AS `column`,
  COLUMN_TYPE                AS `declared_as`,
  IS_NULLABLE                AS `nullable`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'promo_codes'
  AND COLUMN_NAME IN ('site','currency')
ORDER BY COLUMN_NAME;

-- A.2 — which rows Section B is about to park on NULL. Anything listed here has
-- a `site` outside the new 37-region list: the retired 'all' wildcard, a typo, an
-- empty string, or already NULL. All of them are unredeemable TODAY — parking
-- them changes nothing functionally, it only makes the ENUM conversion safe.
-- Expect on a live imartap that ran deploy/08: the 10 'all' rows, all inactive.
-- An ACTIVE row in this list is worth a look before you continue — it is a code
-- someone believes works and does not.
SELECT
  'A.2 rows to be parked on NULL' AS `check`,
  `site`                          AS `current_site`,
  `active`,
  COUNT(*)                        AS `rows`,
  GROUP_CONCAT(`code` ORDER BY `code` SEPARATOR ', ') AS `codes`
FROM `promo_codes`
WHERE `site` IS NULL
   OR `site` NOT IN ('bg','ro','gr','al',
                     'en','md','at','cz','de','es','hr','hu','it','pl','si','sk','cy','uk','us','co',
                     'be','dk','ee','fi','fr','lt','lv','nl','pt','se','mk','rs','ua','tr','ru',
                     'biz','org')
GROUP BY `site`, `active`
ORDER BY `active` DESC, `rows` DESC;


-- ═══════════════════════════════════════════════════════════════════════════
-- Section B — park non-region `site` values on NULL   [imartap]
-- ═══════════════════════════════════════════════════════════════════════════
-- Runs BEFORE the ALTER, while the column is still wide enough to hold them.
-- The old value goes into `note` so the row stays auditable; LEFT(...,255) keeps
-- the result inside note's VARCHAR(255) instead of erroring under STRICT mode.
-- The marker is PREPENDED, not appended: a note already near 255 chars would
-- otherwise have the marker itself chopped off by that LEFT() and the row would
-- lose the only record of what its region used to be.
--
-- On an instance whose `site` is already ENUM('bg','ro','gr','al') NOT NULL this
-- matches 0 rows by definition — the ENUM never let a bad value in. It is only
-- the VARCHAR instances (and deploy/08's 'all' leftovers) that have work here.
UPDATE `promo_codes`
   SET `note` = LEFT(CONCAT('[retired site=', `site`, '] ', COALESCE(`note`, '')), 255)
 WHERE `site` IS NOT NULL
   AND `site` NOT IN ('bg','ro','gr','al',
                      'en','md','at','cz','de','es','hr','hu','it','pl','si','sk','cy','uk','us','co',
                      'be','dk','ee','fi','fr','lt','lv','nl','pt','se','mk','rs','ua','tr','ru',
                      'biz','org');

-- Deactivate them too. deploy/08 already did this for `site = 'all'`; a typo'd
-- region may still be flagged active, and once `site` is NULL nothing in the PHP
-- would ever surface it — an active flag on an unreachable code is just noise.
-- `site IS NULL` is spelled out separately because `NULL NOT IN (…)` evaluates to
-- NULL, not TRUE — without it a pre-existing NULL-site row would stay flagged
-- active and trip check F.4.
UPDATE `promo_codes`
   SET `active` = 0
 WHERE `active` = 1
   AND (`site` IS NULL
    OR  `site` NOT IN ('bg','ro','gr','al',
                       'en','md','at','cz','de','es','hr','hu','it','pl','si','sk','cy','uk','us','co',
                       'be','dk','ee','fi','fr','lt','lv','nl','pt','se','mk','rs','ua','tr','ru',
                       'biz','org'));

-- Two statements, not one: this one must run on a column that still accepts the
-- old value, and it is what makes the Section C conversion lossless.
UPDATE `promo_codes`
   SET `site` = NULL
 WHERE `site` NOT IN ('bg','ro','gr','al',
                      'en','md','at','cz','de','es','hr','hu','it','pl','si','sk','cy','uk','us','co',
                      'be','dk','ee','fi','fr','lt','lv','nl','pt','se','mk','rs','ua','tr','ru',
                      'biz','org');


-- ═══════════════════════════════════════════════════════════════════════════
-- Section C — promo_codes: site → 37 regions, currency → 17   [imartap]
-- ═══════════════════════════════════════════════════════════════════════════
-- No ALGORITHM/LOCK hint on purpose: appending ENUM values is in-place on MySQL
-- 8, but NOT NULL → NULL rebuilds the table, so let the server pick the best it
-- can. promo_codes is a small catalog — this is seconds, not minutes.
ALTER TABLE `promo_codes`
  MODIFY `currency` ENUM('BGN','EUR','ALL','RON',
                         'CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD','RUB','SEK','TRY','UAH','USD')
                    NOT NULL DEFAULT 'BGN'
                    COMMENT 'code currency (ALL = Albanian lek, RON = Romanian leu, MDL = Moldovan leu, MKD = Macedonian denar, RSD = Serbian dinar)',
  MODIFY `site`     ENUM('bg','ro','gr','al',
                         'en','md','at','cz','de','es','hr','hu','it','pl','si','sk','cy','uk','us','co',
                         'be','dk','ee','fi','fr','lt','lv','nl','pt','se','mk','rs','ua','tr','ru',
                         'biz','org')
                    NULL DEFAULT NULL
                    COMMENT 'регионът, за който важи кодът — по един на код, без wildcard (виж PromoCode::SITES). NULL = архивен ред, не се осребрява никъде';


-- ═══════════════════════════════════════════════════════════════════════════
-- Section D — imartap's own copies                    [imartap]
-- ═══════════════════════════════════════════════════════════════════════════
-- D.1 — order_promo_codes on imartap (fresh/07) snapshots promo_codes.currency
-- at finalize, so its ENUM must match promo_codes' exactly or a non-BGN order
-- snapshot truncates on write. Skip this statement if the instance has no
-- imartap copy of the table — it fails with ERROR 1146 and the client stops
-- reading the file there, so D.2 below would never run.
ALTER TABLE `order_promo_codes`
  MODIFY `currency` ENUM('BGN','EUR','ALL','RON',
                         'CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD','RUB','SEK','TRY','UAH','USD')
                    NOT NULL DEFAULT 'BGN'
                    COMMENT 'snapshot of promo_codes.currency at order-finalize';

-- D.2 — currency_rates rows for the 13 new currencies. PromoCode::toBgn() falls
-- back to rate 1.0 for a currency with no row — a `fixed` HUF code would then be
-- deducted 1:1 as BGN — so the rows must exist before any code is authored in
-- them. INSERT IGNORE: `currency` is the PRIMARY KEY, so a re-run (or a currency
-- someone already added by hand) is skipped, never overwritten with the
-- placeholder below.
--
-- Every value here is a PLACEHOLDER of the right order of magnitude, not a quote.
--   source = 'bnb'    → scripts/update-currency-rates.php overwrites it on the
--                       next run. The job is data-driven (it refreshes every
--                       is_fixed = 0 AND source = 'bnb' row), so no code change
--                       is needed; a currency the BNB feed happens to omit is
--                       only logged as `WARN: provider had no rate for …` and
--                       left at its last value.
--   source = 'manual' → BNB does not publish it (same as ALL). NOT refreshed by
--                       anything. MKD and RSD are de-facto euro-pegged so their
--                       placeholders drift slowly; MDL floats and wants a real
--                       rate set by hand before an MDL code is authored.
INSERT IGNORE INTO `currency_rates` (`currency`, `rate_to_bgn`, `is_fixed`, `source`, `updated_at`) VALUES
  ('CZK', 0.07920000, 0, 'bnb',    NULL),
  ('DKK', 0.26220000, 0, 'bnb',    NULL),
  ('GBP', 2.29000000, 0, 'bnb',    NULL),
  ('HUF', 0.00500000, 0, 'bnb',    NULL),
  ('MDL', 0.09900000, 0, 'manual', NULL),
  ('MKD', 0.03180000, 0, 'manual', NULL),
  ('PLN', 0.46000000, 0, 'bnb',    NULL),
  ('RSD', 0.01670000, 0, 'manual', NULL),
  ('RUB', 0.02050000, 0, 'bnb',    NULL),
  ('SEK', 0.17500000, 0, 'bnb',    NULL),
  ('TRY', 0.04700000, 0, 'bnb',    NULL),
  ('UAH', 0.04200000, 0, 'bnb',    NULL),
  ('USD', 1.68000000, 0, 'bnb',    NULL);


-- ═══════════════════════════════════════════════════════════════════════════
-- Section E — the regional pivots      [EVERY regional DB — repeat per region]
-- ═══════════════════════════════════════════════════════════════════════════
-- cart_promo_codes (fresh/01) and order_promo_codes (fresh/02) each snapshot the
-- catalog currency next to the cart. Their ENUMs must match promo_codes' or the
-- snapshot truncates the moment a code in a new currency is applied. There is no
-- `site` column here — the region is implied by which DB you are in.
--
-- NOT to be run on imartap: imartap has no cart_promo_codes, and its
-- order_promo_codes was already handled in D.1.
ALTER TABLE `cart_promo_codes`
  MODIFY `currency` ENUM('BGN','EUR','ALL','RON',
                         'CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD','RUB','SEK','TRY','UAH','USD')
                    NOT NULL DEFAULT 'BGN'
                    COMMENT 'snapshot of promo_codes.currency at apply-time';

ALTER TABLE `order_promo_codes`
  MODIFY `currency` ENUM('BGN','EUR','ALL','RON',
                         'CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD','RUB','SEK','TRY','UAH','USD')
                    NOT NULL DEFAULT 'BGN'
                    COMMENT 'snapshot of promo_codes.currency at order-finalize';


-- ═══════════════════════════════════════════════════════════════════════════
-- Section F — verification (read-only, writes NOTHING)
-- ═══════════════════════════════════════════════════════════════════════════
-- SPLIT BY TARGET — F.1/F.2 run anywhere, F.3–F.5 need `promo_codes` and are
-- imartap-only. On a regional DB they abort with ERROR 1146 (no such table) and
-- the client stops reading the file, so run only F.1/F.2 there.
--
-- F.1 — the ENUMs. Expect 37 regions / 17 currencies on every row, and no 'all'.
-- Counting the commas is how we assert the width without pasting the whole list.
SELECT
  'F.1 enum width'  AS `check`,
  TABLE_NAME        AS `table`,
  COLUMN_NAME       AS `column`,
  (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 AS `values`,
  CASE
    WHEN DATA_TYPE <> 'enum'                                  THEN CONCAT('FAIL — not an ENUM: ', COLUMN_TYPE)
    WHEN COLUMN_NAME = 'site' AND COLUMN_TYPE LIKE '%\'all\'%' THEN 'FAIL — retired wildcard still declared'
    WHEN COLUMN_NAME = 'site'
         AND (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 = 37 THEN 'OK'
    WHEN COLUMN_NAME = 'currency'
         AND (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 = 17 THEN 'OK'
    ELSE 'FAIL — wrong number of values'
  END AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND ((TABLE_NAME = 'promo_codes' AND COLUMN_NAME IN ('site','currency'))
    OR (TABLE_NAME IN ('cart_promo_codes','order_promo_codes') AND COLUMN_NAME = 'currency'))
ORDER BY TABLE_NAME, COLUMN_NAME;

-- F.2 — the first four ENUM values must still be in their original positions.
-- If this FAILs, existing rows were remapped to the wrong region/currency by an
-- earlier hand-written ALTER and the table needs a manual audit.
SELECT
  'F.2 original values kept first' AS `check`,
  TABLE_NAME                       AS `table`,
  COLUMN_NAME                      AS `column`,
  LEFT(COLUMN_TYPE, 40)            AS `starts_with`,
  IF(COLUMN_TYPE LIKE
       IF(COLUMN_NAME = 'site', 'enum(\'bg\',\'ro\',\'gr\',\'al\',%', 'enum(\'BGN\',\'EUR\',\'ALL\',\'RON\',%'),
     'OK', 'FAIL — ordinals shifted, rows may point at the wrong value') AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND ((TABLE_NAME = 'promo_codes' AND COLUMN_NAME IN ('site','currency'))
    OR (TABLE_NAME IN ('cart_promo_codes','order_promo_codes') AND COLUMN_NAME = 'currency'))
ORDER BY TABLE_NAME, COLUMN_NAME;

-- F.3 — nothing got truncated to the empty string by the conversion. Expect 0
-- rows. Any row here means Section B did not run before Section C.   [imartap only]
SELECT
  'F.3 truncated to empty' AS `check`,
  COUNT(*)                 AS `rows`,
  IF(COUNT(*) = 0, 'OK', 'FAIL — Section B was skipped, values were lost') AS `result`
FROM `promo_codes`
WHERE `site` = '' OR `currency` = '';

-- F.4 — region distribution after the migration, parked rows included. Every
-- NULL row must be inactive; an active NULL means a live code lost its region.
-- [imartap only]
-- The alias is `region`, not `site`: GROUP BY `site` would then be ambiguous
-- between the alias and the column and MySQL warns (1052) on every run.
SELECT
  'F.4 site values in use' AS `check`,
  COALESCE(`site`, '(NULL — parked)') AS `region`,
  `active`,
  COUNT(*)                 AS `rows`,
  CASE
    WHEN `site` IS NOT NULL   THEN 'OK'
    WHEN `active` = 0         THEN 'parked — unredeemable by design, kept for audit'
    ELSE 'FAIL — active code with no region, it can never be redeemed'
  END AS `result`
FROM `promo_codes`
GROUP BY `site`, `active`
ORDER BY `rows` DESC;

-- F.5 — every currency a code can be authored in has a rate row. A missing row
-- makes PromoCode::toBgn() fall back to 1.0, so a `fixed` code in that currency
-- is deducted at face value in BGN. Expect 0 rows.   [imartap only]
SELECT
  'F.5 currency without a rate' AS `check`,
  `currency`,
  COUNT(*)                      AS `codes`,
  'FAIL — add a currency_rates row before using this currency' AS `result`
FROM `promo_codes` p
WHERE NOT EXISTS (SELECT 1 FROM `currency_rates` r WHERE r.`currency` = p.`currency`)
GROUP BY `currency`;
