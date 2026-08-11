-- =============================================================================
-- DEPLOY 07 — Extend the `currency` ENUM with 'ALL' (Albanian lek), plain SQL
-- =============================================================================
-- Run MANUALLY, per database. Plain ALTER statements — no guards. Adds 'ALL' to
-- ENUM('BGN','EUR'). MODIFY is safe to re-run (it just sets the same type again).
--
-- WHERE TO RUN:
--   • Section A (`promo_codes`)        → imartap ONLY (catalog / source of truth)
--   • Section B (`order_promo_codes`)  → imartap AND every regional DB
--   • Section C (`cart_promo_codes`)   → regional DBs ONLY
--
-- lib/PromoCode.php converts ALL → BGN via currency_rates. BNB does not publish
-- lek, so its rate is a manual currency_rates row (is_fixed = 0, source 'manual').
-- =============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- Section A — promo_codes   (imartap ONLY)
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE `promo_codes`
  MODIFY COLUMN `currency` ENUM('BGN','EUR','ALL') NOT NULL DEFAULT 'BGN'
  COMMENT 'code currency (ALL = Albanian lek)';


-- ═══════════════════════════════════════════════════════════════════════════
-- Section B — order_promo_codes   (imartap AND every regional DB)
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE `order_promo_codes`
  MODIFY COLUMN `currency` ENUM('BGN','EUR','ALL') NOT NULL DEFAULT 'BGN'
  COMMENT 'snapshot of promo_codes.currency at order-finalize';


-- ═══════════════════════════════════════════════════════════════════════════
-- Section C — cart_promo_codes   (regional DBs ONLY)
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE `cart_promo_codes`
  MODIFY COLUMN `currency` ENUM('BGN','EUR','ALL') NOT NULL DEFAULT 'BGN'
  COMMENT 'snapshot of promo_codes.currency at apply-time';
