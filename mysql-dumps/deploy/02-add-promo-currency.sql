-- =============================================================================
-- DEPLOY 02 — Add `currency` to the promo tables (plain SQL)
-- =============================================================================
-- Run MANUALLY, per database. Plain ALTER statements — no guards, no re-run
-- safety. Run each block ONCE against the intended DB.
--
-- currency ENUM('BGN','EUR') NOT NULL DEFAULT 'BGN'  (== current dev schema)
--
-- WHERE TO RUN:
--   • Section A (`promo_codes`)        → imartap ONLY (catalog / source of truth)
--   • Section B (`order_promo_codes`)  → imartap AND every regional DB
--   • Section C (`cart_promo_codes`)   → regional DBs ONLY
--
-- (An ADD COLUMN on a table that already has `currency` fails with "Duplicate
--  column" — skip that block if it was run before on that DB.)
-- =============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- Section A — promo_codes   (imartap ONLY)
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE `promo_codes`
  ADD COLUMN `currency` ENUM('BGN','EUR') NOT NULL DEFAULT 'BGN'
  COMMENT 'code currency' AFTER `discount_value`;


-- ═══════════════════════════════════════════════════════════════════════════
-- Section B — order_promo_codes   (imartap AND every regional DB)
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE `order_promo_codes`
  ADD COLUMN `currency` ENUM('BGN','EUR') NOT NULL DEFAULT 'BGN'
  COMMENT 'snapshot of promo_codes.currency at order-finalize' AFTER `discount_applied`;


-- ═══════════════════════════════════════════════════════════════════════════
-- Section C — cart_promo_codes   (regional DBs ONLY)
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE `cart_promo_codes`
  ADD COLUMN `currency` ENUM('BGN','EUR') NOT NULL DEFAULT 'BGN'
  COMMENT 'snapshot of promo_codes.currency at apply-time' AFTER `discount_value`;
