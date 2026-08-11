-- =============================================================================
-- DEPLOY 12 — Add `discount_applied` to the item tables (plain SQL)
-- =============================================================================
-- Run MANUALLY, per database. Plain statements — no SET @ddl / PREPARE guards,
-- no re-run safety. Run each block ONCE against the intended DB.
--
-- WHY THIS EXISTS
-- ---------------
-- `discount_applied` (per-line promo discount) is written and read by the promo
-- code all over citte/ — v_casekuk.php, v_case.php, case_potv.php, podavam_za.php,
-- lib/CartItems.php, lib/db-switch.php, … Readers derive the post-promo line
-- total as `it_suma - discount_applied` (see lib/CartItems.php).
--
-- DEPLOY 01 lists `discount_applied DECIMAL(10,2)` under its "ASSUMED STARTING
-- STATE", i.e. it was taken as already present on dev/staging and was therefore
-- never captured in a deploy script. Any DB built from a production dump (which
-- predates the promo work) does NOT have it, and every cart INSERT/UPDATE then
-- dies with:
--     Unknown column 'discount_applied' in 'field list'
-- which silently breaks "add to cart". This script closes that gap.
--
-- WHERE TO RUN:
--   • Section A (`item`)             → imartap AND every regional DB
--   • Section B (`item_l`,`item_no`) → regional DBs ONLY (imartap has neither)
--
-- If a target DB already has the column, the matching ADD COLUMN fails with
-- "Duplicate column name" — that is expected; skip it.
--
-- Ship together with the promo PHP code. NOT NULL DEFAULT 0.00 means existing
-- rows backfill to 0.00, i.e. "no promo discount on this line", which is the
-- correct reading for every pre-promo order.
-- =============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- Section A — `item`   (run on imartap AND every regional DB)
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE `item`
  ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00
  COMMENT 'Per-line promo discount in EUR; post-promo line total = it_suma - discount_applied'
  AFTER `it_suma`;


-- ═══════════════════════════════════════════════════════════════════════════
-- Section B — `item_l`, `item_no`   (regional DBs ONLY)
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE `item_l`
  ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00
  COMMENT 'Per-line promo discount in EUR; post-promo line total = it_suma - discount_applied'
  AFTER `it_suma`;

ALTER TABLE `item_no`
  ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00
  COMMENT 'Per-line promo discount in EUR; post-promo line total = it_suma - discount_applied'
  AFTER `it_suma`;


-- ═══════════════════════════════════════════════════════════════════════════
-- Verify (run per DB)
-- ═══════════════════════════════════════════════════════════════════════════
-- SELECT table_name, column_name, column_type, is_nullable, column_default
--   FROM information_schema.columns
--  WHERE table_schema = DATABASE()
--    AND column_name  = 'discount_applied'
--  ORDER BY table_name;
