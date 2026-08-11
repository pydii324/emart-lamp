-- =============================================================================
-- 03 — item promo/price columns (item, item_l, item_no)
-- Target: ALL DBs — regional (item/item_l/item_no) AND imartap (item master).
-- Run:  mysql -D <regional_db> < 03-add-item-promo-columns.sql
--       mysql -D imartap       < 03-add-item-promo-columns.sql
--
-- Plain SQL, no guards, no prepared statements. NOT idempotent: on a re-run or a
-- non-empty target MySQL raises an error and aborts — that error is the signal.
-- Baseline: a DB with NOTHING promo-related (original pre-migration schema) — the
-- table already has the ORIGINAL stored price columns `it_cena` FLOAT and
-- `it_suma` FLOAT, and none of the promo columns below exist yet. Purely ADDITIVE.
--
-- Columns added:
--   discount_applied  DECIMAL(10,2)  per-line promo delta (cart writes it)
--   it_cena_new   FLOAT     )  Svetlyo/ERP-owned "final after promo" columns.
--   it_suma_new   FLOAT     )  NOT written by us — the storefront only READS them
--   item_br_new   INT       )  (moiteporachkipregled.php, v_cases.php).
--   promot_new    VARCHAR(20))
-- =============================================================================

-- ── item_l ───────────────────────────────────────────────────────────────────
ALTER TABLE `item_l`
  ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT 'promo discount applied to this line',
  ADD COLUMN `it_cena_new` FLOAT NULL DEFAULT NULL COMMENT 'Final unit price after promo — written by ERP',
  ADD COLUMN `it_suma_new` FLOAT NULL DEFAULT NULL COMMENT 'Final line total after promo — written by ERP',
  ADD COLUMN `item_br_new` INT NULL DEFAULT NULL COMMENT 'Final quantity after promo — written by ERP',
  ADD COLUMN `promot_new` VARCHAR(20) NULL DEFAULT NULL COMMENT 'Promo marker after promo — written by ERP';

-- ── item_no ──────────────────────────────────────────────────────────────────
ALTER TABLE `item_no`
  ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT 'promo discount applied to this line',
  ADD COLUMN `it_cena_new` FLOAT NULL DEFAULT NULL COMMENT 'Final unit price after promo — written by ERP',
  ADD COLUMN `it_suma_new` FLOAT NULL DEFAULT NULL COMMENT 'Final line total after promo — written by ERP',
  ADD COLUMN `item_br_new` INT NULL DEFAULT NULL COMMENT 'Final quantity after promo — written by ERP',
  ADD COLUMN `promot_new` VARCHAR(20) NULL DEFAULT NULL COMMENT 'Promo marker after promo — written by ERP';

-- ── item (finalized order lines; master in imartap + regional replica) ────────
ALTER TABLE `item`
  ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT 'promo discount applied to this line',
  ADD COLUMN `it_cena_new` FLOAT NULL DEFAULT NULL COMMENT 'Final unit price after promo — written by ERP',
  ADD COLUMN `it_suma_new` FLOAT NULL DEFAULT NULL COMMENT 'Final line total after promo — written by ERP',
  ADD COLUMN `item_br_new` INT NULL DEFAULT NULL COMMENT 'Final quantity after promo — written by ERP',
  ADD COLUMN `promot_new` VARCHAR(20) NULL DEFAULT NULL COMMENT 'Promo marker after promo — written by ERP';
