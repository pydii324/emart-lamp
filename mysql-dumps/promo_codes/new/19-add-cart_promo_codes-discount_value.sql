-- =============================================================================
-- 19-add-cart_promo_codes-discount_value.sql
-- =============================================================================
-- Adds discount_value to the regional cart_promo_codes table.
--
-- WHY: promo_codes (catalog) lives in imartap which may be on a separate MySQL
-- host from the regional DB. Storing a snapshot of discount_value at apply-time
-- lets promo_recalc() and podavam_za.php finalize compute shipping_percent
-- amounts and PromoCalc totals without a cross-host catalog lookup.
--
-- Run against: every REGIONAL DB that already has cart_promo_codes (issue #610
-- Q1: inmarta and any other region migrated with new/14). NOT imartap (the
-- original imartap cart_promo_codes is dropped by new/18; this column goes on
-- the regional copy).
--
-- Idempotent: IF NOT EXISTS guard.
-- =============================================================================

ALTER TABLE cart_promo_codes
  ADD COLUMN IF NOT EXISTS `discount_value` DECIMAL(10,2) NOT NULL DEFAULT 0.00
    COMMENT 'Snapshot of promo_codes.discount_value at apply-time (% or lv.); avoids cross-host catalog read at recalc/finalize'
    AFTER `discount_applied`;
