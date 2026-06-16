-- =============================================================================
-- Verification (per DB) — изпълни срещу ВСЯКА база през batch tool-а
-- =============================================================================
-- Само SELECT-и, таргетира DATABASE() — без USE, за да работи коректно срещу
-- всяка регионална база + imartap при batch run.
-- =============================================================================

-- Phase 2 колоните (per свързаната DB; *_l/*_no съществуват само в регионалните).
SELECT TABLE_NAME, COLUMN_NAME, COLUMN_TYPE, COLUMN_DEFAULT
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND ((TABLE_NAME IN ('item','item_l','item_no')             AND COLUMN_NAME = 'discount_applied')
    OR (TABLE_NAME IN ('porachki','porachki_l','porachki_no') AND COLUMN_NAME = 'pordost_coupon_discount'))
ORDER BY TABLE_NAME;

-- Промо таблици: очаквано 3 в imartap, 0 в per-site базите.
SELECT DATABASE() AS db,
       SUM(TABLE_NAME = 'promo_codes')       AS has_promo_codes,
       SUM(TABLE_NAME = 'cart_promo_codes')  AS has_cart_promo_codes,
       SUM(TABLE_NAME = 'order_promo_codes') AS has_order_promo_codes
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('promo_codes','cart_promo_codes','order_promo_codes');
