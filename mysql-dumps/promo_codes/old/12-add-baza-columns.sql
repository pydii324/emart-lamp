-- Phase 1 (frozen cenni, pre-promo) schema additions.
-- Adds:
--   it_cena_baza FLOAT, it_suma_baza FLOAT on item_l, item_no, item
--
-- Three price phases (issue #610): keep Phase 1 in its OWN columns instead of
-- deriving it as (it_suma + discount_applied). The derived form desynced when a
-- cart writer rewrote it_suma from cenni() without zeroing discount_applied
-- (e.g. quantity change), corrupting the recalc. With it_suma_baza frozen at
-- add-to-cart, Phase 1 is authoritative.
--   Phase 0 — it_osnovna_cena (catalog, no discount)
--   Phase 1 — it_cena_baza / it_suma_baza (THIS file: lowest cenni, pre-promo)
--   Phase 2 — it_cena / it_suma (after promo; sent to Microinvest)
--   audit   — discount_applied = it_suma_baza - it_suma
--
-- Identical to new/13-add-baza-columns.sql (the fresh-install copy). Idempotent
-- + table-existence safe (same guard pattern as 08-add-phase2-columns.sql): each
-- ALTER runs only when the table exists in DATABASE() AND the column is missing;
-- the backfill runs only when the column exists. Safe via sql-batch-dbs.ts
-- against every region (regional DBs hold item_l/item_no; item master lives in
-- imartap + regional replica). Re-running is a no-op. Backfill relies on
-- discount_applied (added by 08-add-phase2-columns.sql) being present.
-- No stored procedures (the batch splitter splits on ';').

-- ── item_l ───────────────────────────────────────────────────────────────────
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l' AND COLUMN_NAME = 'it_suma_baza'),
  'ALTER TABLE `item_l` ADD COLUMN `it_cena_baza` FLOAT NULL DEFAULT NULL COMMENT ''Phase 1 unit price (frozen cenni, pre-promo)'', ADD COLUMN `it_suma_baza` FLOAT NULL DEFAULT NULL COMMENT ''Phase 1 line total (frozen cenni, pre-promo)''',
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
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no' AND COLUMN_NAME = 'it_suma_baza'),
  'ALTER TABLE `item_no` ADD COLUMN `it_cena_baza` FLOAT NULL DEFAULT NULL COMMENT ''Phase 1 unit price (frozen cenni, pre-promo)'', ADD COLUMN `it_suma_baza` FLOAT NULL DEFAULT NULL COMMENT ''Phase 1 line total (frozen cenni, pre-promo)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no' AND COLUMN_NAME = 'it_suma_baza'),
  'UPDATE `item_no` SET `it_suma_baza` = `it_suma` + `discount_applied`, `it_cena_baza` = (`it_suma` + `discount_applied`) / GREATEST(`item_br`, 1) WHERE `it_suma_baza` IS NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

-- ── item (finalized order lines; master in imartap + regional replica) ────────
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item' AND COLUMN_NAME = 'it_suma_baza'),
  'ALTER TABLE `item` ADD COLUMN `it_cena_baza` FLOAT NULL DEFAULT NULL COMMENT ''Phase 1 unit price (frozen cenni, pre-promo)'', ADD COLUMN `it_suma_baza` FLOAT NULL DEFAULT NULL COMMENT ''Phase 1 line total (frozen cenni, pre-promo)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item' AND COLUMN_NAME = 'it_suma_baza'),
  'UPDATE `item` SET `it_suma_baza` = `it_suma` + `discount_applied`, `it_cena_baza` = (`it_suma` + `discount_applied`) / GREATEST(`item_br`, 1) WHERE `it_suma_baza` IS NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
