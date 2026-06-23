-- =============================================================================
-- 06 — Add promo columns to item tables
-- Target: all DBs (imartap + regional)
-- Idempotent: each ALTER guarded by table + column existence
-- Adds:
--   discount_applied  DECIMAL(10,2) on item, item_l, item_no  (Phase 2 audit delta)
--   it_cena_baza      FLOAT         on item, item_l, item_no  (Phase 1 frozen unit price)
--   it_suma_baza      FLOAT         on item, item_l, item_no  (Phase 1 frozen line total)
-- Backfills baza columns from existing data where NULL.
-- =============================================================================

-- ── item_l ───────────────────────────────────────────────────────────────────
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l' AND COLUMN_NAME = 'discount_applied'),
  'ALTER TABLE `item_l` ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l' AND COLUMN_NAME = 'it_suma_baza'),
  'ALTER TABLE `item_l` ADD COLUMN `it_cena_baza` FLOAT NULL DEFAULT NULL, ADD COLUMN `it_suma_baza` FLOAT NULL DEFAULT NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l' AND COLUMN_NAME = 'it_suma_baza'),
  'UPDATE `item_l` SET `it_suma_baza` = `it_suma` + `discount_applied`, `it_cena_baza` = (`it_suma` + `discount_applied`) / GREATEST(`item_br`, 1) WHERE `it_suma_baza` IS NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

-- ── item_no ──────────────────────────────────────────────────────────────────
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no' AND COLUMN_NAME = 'discount_applied'),
  'ALTER TABLE `item_no` ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no' AND COLUMN_NAME = 'it_suma_baza'),
  'ALTER TABLE `item_no` ADD COLUMN `it_cena_baza` FLOAT NULL DEFAULT NULL, ADD COLUMN `it_suma_baza` FLOAT NULL DEFAULT NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no' AND COLUMN_NAME = 'it_suma_baza'),
  'UPDATE `item_no` SET `it_suma_baza` = `it_suma` + `discount_applied`, `it_cena_baza` = (`it_suma` + `discount_applied`) / GREATEST(`item_br`, 1) WHERE `it_suma_baza` IS NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

-- ── item ─────────────────────────────────────────────────────────────────────
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item' AND COLUMN_NAME = 'discount_applied'),
  'ALTER TABLE `item` ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item' AND COLUMN_NAME = 'it_suma_baza'),
  'ALTER TABLE `item` ADD COLUMN `it_cena_baza` FLOAT NULL DEFAULT NULL, ADD COLUMN `it_suma_baza` FLOAT NULL DEFAULT NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item' AND COLUMN_NAME = 'it_suma_baza'),
  'UPDATE `item` SET `it_suma_baza` = `it_suma` + `discount_applied`, `it_cena_baza` = (`it_suma` + `discount_applied`) / GREATEST(`item_br`, 1) WHERE `it_suma_baza` IS NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
