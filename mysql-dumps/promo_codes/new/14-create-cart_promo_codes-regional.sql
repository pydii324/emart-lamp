-- =============================================================================
-- cart_promo_codes — REGIONAL pivot (issue #610, Q1: pivots move per-site)
-- =============================================================================
-- Lives in the per-site/regional DB, next to the cart (item_l/item_no,
-- porachki_l/porachki_no) — NOT in imartap. `promo_codes` remains the
-- single-source catalog in imartap, referenced by `promo_code_id` WITHOUT a
-- cross-DB foreign key (MySQL cannot enforce a FK across schemas; integrity is
-- enforced in PHP at apply/validate via imartap.promo_codes).
--
-- Idempotent: CREATE TABLE IF NOT EXISTS. Safe to run against imartap too — the
-- original cart_promo_codes already exists there, so IF NOT EXISTS is a no-op
-- and the imartap copy (with its FK) is untouched. Run against each regional DB
-- (now: inmarta). Cleared on order finalize (PromoCode::finalizeForOrder()).
--
-- The `type` ENUM already includes `shipping_percent` (issue #610, Q3) so a
-- fresh regional install needs no follow-up ALTER.
-- =============================================================================

CREATE TABLE IF NOT EXISTS `cart_promo_codes` (
  `id`               INT           NOT NULL AUTO_INCREMENT,
  `cart_id`          INT           NOT NULL,
  `cart_type`        ENUM('l','no') NOT NULL COMMENT 'l = porachki_l logged-in, no = porachki_no guest',
  `promo_code_id`    INT           NOT NULL COMMENT 'imartap.promo_codes.id (no cross-DB FK)',
  `code`             VARCHAR(50)   NOT NULL,
  `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '0 for shipping types; real deduction for percent/fixed',
  `discount_value`   DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT 'Snapshot of promo_codes.discount_value at apply-time (% or lv.); avoids cross-host catalog read at recalc/finalize',
  `type`             ENUM('percent','fixed','shipping','shipping_percent') NOT NULL,
  `shipping_cap`     DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'shipping/shipping_percent only (flat cap on the discount)',
  `created_at`       VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_cart_promo` (`cart_id`, `cart_type`, `promo_code_id`),
  KEY `idx_promo_code` (`promo_code_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
