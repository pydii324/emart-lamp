-- =============================================================================
-- 07 — Add promo columns to porachki tables
-- Target: all DBs (imartap + regional)
-- Idempotent: each ALTER guarded by table + column existence
-- Adds:
--   pordost_coupon_discount DECIMAL(10,2) on porachki, porachki_l, porachki_no
--   promo_fixed_discount    DECIMAL(10,2) on porachki_l, porachki_no
-- =============================================================================

-- ── porachki (imartap master) ─────────────────────────────────────────────────
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki' AND COLUMN_NAME = 'pordost_coupon_discount'),
  'ALTER TABLE `porachki` ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

-- ── porachki_l ────────────────────────────────────────────────────────────────
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_l' AND COLUMN_NAME = 'pordost_coupon_discount'),
  'ALTER TABLE `porachki_l` ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_l' AND COLUMN_NAME = 'promo_fixed_discount'),
  'ALTER TABLE `porachki_l` ADD COLUMN `promo_fixed_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

-- ── porachki_no ───────────────────────────────────────────────────────────────
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_no' AND COLUMN_NAME = 'pordost_coupon_discount'),
  'ALTER TABLE `porachki_no` ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_no' AND COLUMN_NAME = 'promo_fixed_discount'),
  'ALTER TABLE `porachki_no` ADD COLUMN `promo_fixed_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
