-- Mini-cart fixed (voucher) discount — regional cart-header column.
-- Adds:
--   promo_fixed_discount DECIMAL(10,2) on porachki_l, porachki_no
--
-- Why (issue #610): the fixed/voucher discount is order-level (not baked into
-- item_l lines like percent), so the mini-cart in header.php — which reads
-- SUM(it_suma) FROM item_l/item_no on EVERY page and never runs promo_recalc —
-- showed an inflated total. promo_recalc() now persists the fixed total onto the
-- cart header so dumb readers can show the net (SUM(it_suma) - promo_fixed_discount)
-- without touching the imartap promo tables. percent is already in it_suma;
-- shipping uses the existing pordost_coupon_discount.
--
-- Identical to new/14-add-promo-fixed-discount-cart.sql (fresh-install copy).
-- Idempotent + table-existence safe (same guard pattern as
-- 08-add-phase2-columns.sql): runs only when the table exists in DATABASE() and
-- the column is missing. porachki_l/porachki_no are regional cart headers (no-op
-- against imartap). Re-running is a no-op.
-- No stored procedures (the batch splitter splits on ';').

-- porachki_l.promo_fixed_discount
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_l' AND COLUMN_NAME = 'promo_fixed_discount'),
  'ALTER TABLE `porachki_l` ADD COLUMN `promo_fixed_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT ''Order-level fixed/voucher promo total on the cart (mini-cart net display)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

-- porachki_no.promo_fixed_discount
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_no' AND COLUMN_NAME = 'promo_fixed_discount'),
  'ALTER TABLE `porachki_no` ADD COLUMN `promo_fixed_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT ''Order-level fixed/voucher promo total on the cart (mini-cart net display)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
