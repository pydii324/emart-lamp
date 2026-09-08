-- =============================================================================
-- 15 — promo money columns: say which currency they are in
-- Target: imartap AND every regional DB (see WHICH TABLE WHERE below).
-- Run:  mysql -D imartap        < 15-promo-currency-is-region-currency.sql
--       mysql -D <regional_db>  < 15-promo-currency-is-region-currency.sql
--
-- COMMENT-only. No column is added, dropped or retyped and no row is touched, so
-- this is ALGORITHM=INSTANT and re-runnable (a second run re-declares the same
-- thing and succeeds — unlike the rest of deploy/, there is no state to signal).
--
-- WHAT IT DOCUMENTS
--   A region has exactly ONE currency. Its cart (item_l / item_no) is priced in
--   it — the catalog is EUR, but prices convert on the way in via `kurs`, which
--   is what porachki.valuta / porachki.kurs record — and its promo codes are
--   authored in it (PromoCode::SITE_CURRENCY -> promo_codes.currency).
--
--     code currency == cart currency == region currency
--
--   So every money column in these two tables is in `currency`, including
--   discount_applied. Nothing in the promo path converts. Until now the only
--   column stating its unit was none of them: discount_applied had no COMMENT at
--   all in order_promo_codes, and cart_promo_codes.discount_value claimed to be a
--   plain catalog snapshot while the PHP was storing a converted value.
--
-- ⚠ HISTORICAL ROWS MAY BE MISPRICED — READ BEFORE ASSUMING THIS IS COSMETIC
--   The PHP this migration accompanies removes a EUR conversion layer that ran on
--   every catalog amount (PromoCode::toEur against imartap.currency_rates). In a
--   non-EUR region that conversion re-priced a code against a cart already in the
--   same currency, so the discount landed wrong by the whole rate:
--     RON (rate ~0.20) — a 50 RON voucher deducted ~10.06 RON  (~5x too little)
--     GBP (rate ~1.17) — a 50 GBP voucher deducted ~58.50 GBP  (too much)
--   EUR regions are unaffected (rate 1.0), which is most of SITE_CURRENCY and why
--   this could sit unnoticed. Query D below lists what is actually on disk.
--   Whether anything needs correcting is a business call, not a migration: past
--   orders are settled and the fix is per-customer, not per-row.
--
-- WHICH TABLE WHERE
--   cart_promo_codes  — regional DBs only.
--   order_promo_codes — imartap AND every regional DB (dual-write; imartap is the
--                       autoincrement master, see lib/PromoCode.php::finalize).
--   A DB without one of the tables errors on that statement — expected; run the
--   file per DB and ignore the block that does not apply there.
--
-- NOTE: imartap.currency_rates is now read by nothing in this repo. It is left in
--   place deliberately — dropping it is a separate decision, and the table is the
--   only record of the rates those historical rows were written at.
-- =============================================================================

-- ── cart_promo_codes (regional only) ────────────────────────────────────────
ALTER TABLE `cart_promo_codes`
  MODIFY `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT '0.00'
    COMMENT 'in `currency` — 0 for shipping types, real deduction for percent/fixed',
  MODIFY `discount_value`   DECIMAL(10,2) NOT NULL DEFAULT '0.00'
    COMMENT 'promo_codes.discount_value at apply-time, in `currency` — unconverted',
  MODIFY `shipping_cap`     DECIMAL(10,2) DEFAULT NULL
    COMMENT 'promo_codes.shipping_cap, in `currency` — flat cap on the discount, NULL = uncapped';

-- The ENUM is re-declared byte-identically on purpose: MODIFY replaces the whole
-- definition, so omitting it would silently drop the value list and the default.
ALTER TABLE `cart_promo_codes`
  MODIFY `currency` ENUM('BGN','EUR','ALL','RON',
                         'CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD','RUB','SEK','TRY','UAH','USD','CAD')
                    NOT NULL DEFAULT 'EUR'
                    COMMENT 'snapshot of promo_codes.currency at apply-time — the unit of EVERY amount in this row';

-- ── order_promo_codes (imartap AND regional) ────────────────────────────────
ALTER TABLE `order_promo_codes`
  MODIFY `discount_applied` DECIMAL(10,2) NOT NULL
    COMMENT 'in `currency` — the amount actually deducted from the order';

ALTER TABLE `order_promo_codes`
  MODIFY `currency` ENUM('BGN','EUR','ALL','RON',
                         'CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD','RUB','SEK','TRY','UAH','USD','CAD')
                    NOT NULL DEFAULT 'EUR'
                    COMMENT 'snapshot of promo_codes.currency at order-finalize — the unit of discount_applied';

-- ── verify ──────────────────────────────────────────────────────────────────
SELECT
  'A. every money column names its unit' AS `check`,
  TABLE_NAME                             AS `table`,
  COLUMN_NAME                            AS `column`,
  LEFT(COLUMN_COMMENT, 44)               AS `comment_starts`,
  IF(COLUMN_COMMENT LIKE '%`currency`%', 'OK',
     'FAIL — comment must point at the `currency` column') AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('cart_promo_codes','order_promo_codes')
  AND COLUMN_NAME IN ('discount_applied','discount_value','shipping_cap')
ORDER BY TABLE_NAME, COLUMN_NAME;

-- B. MODIFY must not have eaten the ENUM or its default.
SELECT
  'B. currency ENUM intact'  AS `check`,
  TABLE_NAME                 AS `table`,
  COLUMN_DEFAULT             AS `default`,
  CASE
    WHEN COLUMN_TYPE NOT LIKE 'enum(\'BGN\',\'EUR\',\'ALL\',\'RON\',%' THEN 'FAIL — value list changed'
    WHEN COLUMN_DEFAULT <> 'EUR'                                       THEN 'FAIL — default lost'
    WHEN IS_NULLABLE <> 'NO'                                           THEN 'FAIL — must be NOT NULL'
    ELSE 'OK'
  END AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('cart_promo_codes','order_promo_codes')
  AND COLUMN_NAME = 'currency'
ORDER BY TABLE_NAME;

-- C. Every currency present must be one a region actually authors in.
--    A value outside PromoCode::SITE_CURRENCY means a code was generated for a
--    region that is not in the map, or the ENUM drifted from the PHP.
SELECT
  'C. currencies in use'   AS `check`,
  `currency`               AS `currency`,
  COUNT(*)                 AS `rows`
FROM `order_promo_codes`
GROUP BY `currency`
ORDER BY `rows` DESC;

-- D. ⚠ Rows written while the removed EUR conversion was live. Non-EUR rows here
--    are mispriced by their rate (see the header). EUR rows were always correct.
--    This reports; it does not change anything.
SELECT
  'D. pre-fix non-EUR rows' AS `check`,
  `currency`                AS `currency`,
  COUNT(*)                  AS `rows`,
  ROUND(SUM(`discount_applied`), 2) AS `total_as_stored`,
  MIN(`created_at`)         AS `first`,
  MAX(`created_at`)         AS `last`
FROM `order_promo_codes`
WHERE `currency` <> 'EUR'
GROUP BY `currency`
ORDER BY `rows` DESC;
