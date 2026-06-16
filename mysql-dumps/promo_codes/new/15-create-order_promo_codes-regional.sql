-- =============================================================================
-- order_promo_codes — REGIONAL pivot (issue #610, Q1: pivots move per-site)
-- =============================================================================
-- Source of truth for finalized promo usage, stored next to the regional order
-- (porachki). `promo_code_id` references the imartap catalog WITHOUT a cross-DB
-- foreign key. The global counter imartap.promo_codes.times_used is still
-- incremented in parallel by PromoCode::markUsed().
--
-- Idempotent: CREATE TABLE IF NOT EXISTS. Safe to run against imartap too (the
-- original already exists there → no-op). Run against each regional DB (now:
-- inmarta).
--
-- NOTE: historical rows in imartap.order_promo_codes are NOT migrated here —
-- usage history written before this change stays in imartap. A per-region data
-- backfill (order_id -> region) is a separate task (see plan: Рискове).
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
