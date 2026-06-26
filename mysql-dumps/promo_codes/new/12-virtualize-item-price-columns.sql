-- =============================================================================
-- 12 — Virtualize Phase-2 price columns on item tables
-- Target: all DBs (imartap holds `item`; regional DBs hold item/item_l/item_no)
-- Requires: 06-add-item-columns.sql (it_cena_baza / it_suma_baza / discount_applied)
--
-- Turns it_cena, it_suma into VIRTUAL generated columns and adds a new generated
-- it_cena_suma. Phase-2 (post-promo, sent to Microinvest) is now DERIVED on the
-- fly from Phase-1 frozen columns + the promo delta, so the invariant can never
-- desync from the writers again:
--   it_cena     = ROUND(GREATEST((it_suma_baza - discount_applied) / GREATEST(item_br,1), 0), 2)
--   it_suma     = ROUND(GREATEST( it_suma_baza - discount_applied, 0), 2)
--   it_cena_suma= ROUND( it_cena_baza * item_br, 2)             -- NEW (unit x qty)
-- GREATEST(...,0) mirrors applyItemDiscounts clamping a >line-total discount to 0
-- (so over-discounted rows reproduce as 0 instead of going negative).
-- This reproduces every existing row exactly: applyItemDiscounts wrote
--   it_suma = ROUND(phase1_suma - disc, 2) with phase1_suma = it_suma_baza,
--   discount_applied = disc; no-promo rows have discount_applied = 0; backfilled
--   rows have it_suma_baza = it_suma + discount_applied. COALESCE guards pre-baza
--   NULLs; GREATEST(item_br,1) guards /0.
--
-- MySQL cannot convert a non-generated column to VIRTUAL in place, so each
-- column is DROP-ped (only when still non-generated) and re-ADD-ed AFTER its
-- original neighbour to preserve column order for positional readers.
--
-- Idempotent + table-existence safe (same SET @ddl / PREPARE pattern as
-- 06-add-item-columns.sql; no stored procedures — the batch splitter splits on
-- ';'). Re-running is a no-op. Identical to old/20-virtualize-item-price-columns.sql.
--
-- NOTE: the 6 cart writers (lib/CartItems.php applyItemDiscounts + v_case*.php)
-- must STOP assigning it_cena/it_suma in their INSERT/UPDATE — generated columns
-- are read-only. Ship this migration together with that PHP change.
-- =============================================================================

-- ── item_l ───────────────────────────────────────────────────────────────────
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l' AND COLUMN_NAME = 'it_cena' AND GENERATION_EXPRESSION = ''),
  'ALTER TABLE `item_l` DROP COLUMN `it_cena`',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l' AND COLUMN_NAME = 'it_suma' AND GENERATION_EXPRESSION = ''),
  'ALTER TABLE `item_l` DROP COLUMN `it_suma`',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l' AND COLUMN_NAME = 'it_cena'),
  'ALTER TABLE `item_l` ADD COLUMN `it_cena` FLOAT GENERATED ALWAYS AS (ROUND(GREATEST((COALESCE(`it_suma_baza`,0) - `discount_applied`) / GREATEST(`item_br`,1), 0), 2)) VIRTUAL NOT NULL AFTER `item_br`',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l' AND COLUMN_NAME = 'it_suma'),
  'ALTER TABLE `item_l` ADD COLUMN `it_suma` FLOAT GENERATED ALWAYS AS (ROUND(GREATEST(COALESCE(`it_suma_baza`,0) - `discount_applied`, 0), 2)) VIRTUAL NOT NULL AFTER `it_cena`',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l' AND COLUMN_NAME = 'it_cena_suma'),
  'ALTER TABLE `item_l` ADD COLUMN `it_cena_suma` FLOAT GENERATED ALWAYS AS (ROUND(COALESCE(`it_cena_baza`,0) * `item_br`, 2)) VIRTUAL COMMENT ''Unit baza price x quantity (it_cena_baza * item_br)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

-- ── item_no ──────────────────────────────────────────────────────────────────
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no' AND COLUMN_NAME = 'it_cena' AND GENERATION_EXPRESSION = ''),
  'ALTER TABLE `item_no` DROP COLUMN `it_cena`',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no' AND COLUMN_NAME = 'it_suma' AND GENERATION_EXPRESSION = ''),
  'ALTER TABLE `item_no` DROP COLUMN `it_suma`',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no' AND COLUMN_NAME = 'it_cena'),
  'ALTER TABLE `item_no` ADD COLUMN `it_cena` FLOAT GENERATED ALWAYS AS (ROUND(GREATEST((COALESCE(`it_suma_baza`,0) - `discount_applied`) / GREATEST(`item_br`,1), 0), 2)) VIRTUAL NOT NULL AFTER `item_br`',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no' AND COLUMN_NAME = 'it_suma'),
  'ALTER TABLE `item_no` ADD COLUMN `it_suma` FLOAT GENERATED ALWAYS AS (ROUND(GREATEST(COALESCE(`it_suma_baza`,0) - `discount_applied`, 0), 2)) VIRTUAL NOT NULL AFTER `it_cena`',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no' AND COLUMN_NAME = 'it_cena_suma'),
  'ALTER TABLE `item_no` ADD COLUMN `it_cena_suma` FLOAT GENERATED ALWAYS AS (ROUND(COALESCE(`it_cena_baza`,0) * `item_br`, 2)) VIRTUAL COMMENT ''Unit baza price x quantity (it_cena_baza * item_br)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

-- ── item (finalized order lines; master in imartap + regional replica) ────────
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item' AND COLUMN_NAME = 'it_cena' AND GENERATION_EXPRESSION = ''),
  'ALTER TABLE `item` DROP COLUMN `it_cena`',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item' AND COLUMN_NAME = 'it_suma' AND GENERATION_EXPRESSION = ''),
  'ALTER TABLE `item` DROP COLUMN `it_suma`',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item' AND COLUMN_NAME = 'it_cena'),
  'ALTER TABLE `item` ADD COLUMN `it_cena` FLOAT GENERATED ALWAYS AS (ROUND(GREATEST((COALESCE(`it_suma_baza`,0) - `discount_applied`) / GREATEST(`item_br`,1), 0), 2)) VIRTUAL NOT NULL AFTER `item_br`',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item' AND COLUMN_NAME = 'it_suma'),
  'ALTER TABLE `item` ADD COLUMN `it_suma` FLOAT GENERATED ALWAYS AS (ROUND(GREATEST(COALESCE(`it_suma_baza`,0) - `discount_applied`, 0), 2)) VIRTUAL NOT NULL AFTER `it_cena`',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item' AND COLUMN_NAME = 'it_cena_suma'),
  'ALTER TABLE `item` ADD COLUMN `it_cena_suma` FLOAT GENERATED ALWAYS AS (ROUND(COALESCE(`it_cena_baza`,0) * `item_br`, 2)) VIRTUAL COMMENT ''Unit baza price x quantity (it_cena_baza * item_br)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
