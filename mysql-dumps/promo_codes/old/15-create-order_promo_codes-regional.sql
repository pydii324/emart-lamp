-- =============================================================================
-- order_promo_codes — REGIONAL pivot (issue #610, Q1: pivots move per-site)
-- =============================================================================
-- OLD-PATH copy of new/15-create-order_promo_codes-regional.sql (identical SQL).
-- Creates the regional usage-history table next to porachki. Run against each
-- regional DB.
--
-- `promo_code_id` references the imartap catalog WITHOUT a cross-DB FK. The
-- global counter imartap.promo_codes.times_used is still incremented by
-- PromoCode::markUsed().
--
-- Idempotent: CREATE TABLE IF NOT EXISTS. Safe against imartap too (no-op).
--
-- NOTE: historical rows in imartap.order_promo_codes are NOT migrated here —
-- usage history written before Q1 stays in imartap (preserved, NOT dropped; the
-- imartap copy is intentionally kept). A per-region history backfill
-- (order_id -> region) is a separate task. New usage goes to the regional table.
-- =============================================================================

CREATE TABLE IF NOT EXISTS `order_promo_codes` (
  `id`                 INT           NOT NULL AUTO_INCREMENT,
  `order_id`           INT           NOT NULL COMMENT 'porachki.porachki_id',
  `promo_code_id`      INT           NOT NULL COMMENT 'imartap.promo_codes.id (no cross-DB FK)',
  `klienti_id`         INT           NOT NULL DEFAULT 0 COMMENT '0 = guest',
  `discount_applied`   DECIMAL(10,2) NOT NULL,
  `used_by_employeeId` INT           NULL DEFAULT NULL COMMENT 'admin/backoffice app; storefront leaves NULL',
  `created_at`         VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_order_promo` (`order_id`, `promo_code_id`),
  KEY `idx_klienti` (`klienti_id`, `promo_code_id`),
  KEY `idx_promo_code` (`promo_code_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
