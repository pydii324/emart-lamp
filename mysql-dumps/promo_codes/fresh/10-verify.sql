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


-- ── E. currency ENUMs carry all 17 currencies ───────────────────────────────
-- promo_codes / cart_promo_codes / order_promo_codes must all declare the same
-- 17 currencies — the four originals BGN/EUR/ALL/RON first (an ENUM stores an
-- ordinal, so those positions are frozen) plus the 13 appended for the non-euro
-- regions. A short ENUM truncates a code in a missing currency on write, and a
-- pivot whose list is shorter than promo_codes' silently loses the snapshot.
-- An instance still on the old four: mysql-dumps/deploy/10-extend-site-and-
-- currency-enums.sql.
SELECT
  'E. currency ENUM' AS `check`,
  TABLE_NAME         AS `table`,
  (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 AS `values`,
  COLUMN_TYPE        AS `enum`,
  -- Width is tested BEFORE order: an instance still on the old four-value ENUM
  -- has no comma after 'RON' and would otherwise be reported as mis-ordered
  -- rather than as short, which sends you looking for the wrong problem.
  CASE
    WHEN (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 <> 17
      THEN 'FAIL — missing a currency (deploy/10 not run?)'
    WHEN COLUMN_TYPE NOT LIKE 'enum(\'BGN\',\'EUR\',\'ALL\',\'RON\',%'
      THEN 'FAIL — the four original currencies must stay first, in order'
    ELSE 'OK'
  END AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND COLUMN_NAME = 'currency'
  AND TABLE_NAME IN ('promo_codes','cart_promo_codes','order_promo_codes')
ORDER BY TABLE_NAME;


-- ── F. promo_codes.site ENUM — 37 regions, and no retired 'all' wildcard ────
-- 'all' used to mean "valid on every region"; it was retired (lib/PromoCode.php
-- matches the region exactly now, deploy/08 deactivated the leftover rows), so
-- 06 ships the 37 storefront regions and nothing else. 'al' = Albania is a real
-- region — one letter away — and must stay. bg/ro/gr/al are the original four
-- and stay in the first four ENUM positions: the column stores an ordinal, so
-- reordering would remap every existing row to a different region.
--
-- The list must equal PromoCode::SITES — a region the ENUM has but the PHP does
-- not is unredeemable, and one the PHP has but the ENUM does not cannot even be
-- written. This check only counts values; the PHP side is the authority on which
-- ones. Note some older DBs (dev imartap) carry `site` as VARCHAR instead: that
-- enforces nothing, so a typo'd region is silently accepted and simply yields a
-- code no storefront can redeem. An instance still on the four-region ENUM:
-- mysql-dumps/deploy/10-extend-site-and-currency-enums.sql.
--
-- `site` is NOT NULL here but NULLable on an instance migrated by deploy/10 —
-- that file parks unconvertible legacy values (the 'all' wildcard, typos) on
-- NULL rather than losing them. Both shapes are fine: NULL matches no region.
SELECT
  'F. site ENUM' AS `check`,
  DATA_TYPE      AS `data_type`,
  (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 AS `values`,
  COLUMN_TYPE    AS `declared_as`,
  CASE
    WHEN DATA_TYPE <> 'enum'          THEN CONCAT('WARN — not an ENUM, no region enforced: ', COLUMN_TYPE)
    WHEN COLUMN_TYPE LIKE '%\'all\'%' THEN 'FAIL — retired wildcard still declared'
    -- Width before order, same reason as check E: the old four-region ENUM ends
    -- at 'al' with no comma and must be reported as short, not as mis-ordered.
    WHEN (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 <> 37
      THEN 'FAIL — region list is out of sync with PromoCode::SITES (deploy/10 not run?)'
    WHEN COLUMN_TYPE NOT LIKE 'enum(\'bg\',\'ro\',\'gr\',\'al\',%'
      THEN 'FAIL — the four original regions must stay first, in order'
    ELSE 'OK'
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
