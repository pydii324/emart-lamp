-- =============================================================================
-- 11 — Per-DB verification (run against each DB via batch tool)
-- Target: all DBs
-- Read-only: only SELECTs
-- =============================================================================

-- Item/porachki promo columns present
SELECT TABLE_NAME, COLUMN_NAME, COLUMN_TYPE
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND (
    (TABLE_NAME IN ('item','item_l','item_no') AND COLUMN_NAME IN ('discount_applied','it_cena_baza','it_suma_baza'))
    OR
    (TABLE_NAME IN ('porachki','porachki_l','porachki_no') AND COLUMN_NAME IN ('pordost_coupon_discount','promo_fixed_discount'))
  )
ORDER BY TABLE_NAME, COLUMN_NAME;

-- Promo pivot tables: expect 0 in imartap, present in regional DBs
SELECT
  DATABASE()                                        AS db,
  SUM(TABLE_NAME = 'promo_codes')                   AS has_promo_codes,
  SUM(TABLE_NAME = 'cart_promo_codes')              AS has_cart_promo_codes,
  SUM(TABLE_NAME = 'order_promo_codes')             AS has_order_promo_codes
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('promo_codes','cart_promo_codes','order_promo_codes');

-- cart_promo_codes schema: key columns present (regional DBs only)
SELECT COLUMN_NAME, COLUMN_TYPE
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'cart_promo_codes'
  AND COLUMN_NAME IN ('discount_value','subtype','type','shipping_cap')
ORDER BY COLUMN_NAME;
