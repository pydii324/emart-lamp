-- Phase 2 (promo-inside-product) schema additions.
-- Adds:
--   discount_applied        DECIMAL(10,2) on item_l, item_no, item        (per-line promo audit)
--   pordost_coupon_discount DECIMAL(10,2) on porachki, porachki_l, porachki_no (shipping promo audit/UI)
--
-- Idempotent + table-existence safe: each ALTER runs only when the table
-- exists in the connected DB AND the column is missing. Targets DATABASE()
-- so it is safe to run via sql-batch-dbs.ts against every region (regional
-- DBs hold the *_l/*_no cart tables; imartap holds the item/porachki masters).
-- Re-running is a no-op. No stored procedures (the batch splitter splits on ';').

-- item_l.discount_applied
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l' AND COLUMN_NAME = 'discount_applied'),
  'ALTER TABLE `item_l` ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT ''Phase 2 promo discount on the line (audit)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

-- item_no.discount_applied
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no' AND COLUMN_NAME = 'discount_applied'),
  'ALTER TABLE `item_no` ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT ''Phase 2 promo discount on the line (audit)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

-- item.discount_applied
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item' AND COLUMN_NAME = 'discount_applied'),
  'ALTER TABLE `item` ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT ''Phase 2 promo discount on the line (audit)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

-- porachki.pordost_coupon_discount
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki' AND COLUMN_NAME = 'pordost_coupon_discount'),
  'ALTER TABLE `porachki` ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT ''Shipping promo discount (audit/UI)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

-- porachki_l.pordost_coupon_discount
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_l' AND COLUMN_NAME = 'pordost_coupon_discount'),
  'ALTER TABLE `porachki_l` ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT ''Shipping promo discount (audit/UI)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

-- porachki_no.pordost_coupon_discount
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_no' AND COLUMN_NAME = 'pordost_coupon_discount'),
  'ALTER TABLE `porachki_no` ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT ''Shipping promo discount (audit/UI)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
