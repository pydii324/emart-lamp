-- Verification for Phase 2 schema (run per DB).

-- New columns present (per connected DB; *_l/*_no only exist on regional DBs).
SELECT TABLE_NAME, COLUMN_NAME, COLUMN_TYPE, COLUMN_DEFAULT
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND ((TABLE_NAME IN ('item','item_l','item_no')        AND COLUMN_NAME = 'discount_applied')
    OR (TABLE_NAME IN ('porachki','porachki_l','porachki_no') AND COLUMN_NAME = 'pordost_coupon_discount'))
ORDER BY TABLE_NAME;

-- Promo tables: expect 3 in imartap, 0 in per-site DBs after consolidation.
SELECT DATABASE() AS db,
       SUM(TABLE_NAME = 'promo_codes')       AS has_promo_codes,
       SUM(TABLE_NAME = 'cart_promo_codes')  AS has_cart_promo_codes,
       SUM(TABLE_NAME = 'order_promo_codes') AS has_order_promo_codes
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('promo_codes','cart_promo_codes','order_promo_codes');
