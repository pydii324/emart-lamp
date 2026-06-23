-- =============================================================================
-- 09 — cart_promo_codes (regional pivot, no FK)
-- Target: regional DBs only — NOT imartap
-- Idempotent: CREATE TABLE IF NOT EXISTS
-- No foreign key: promo_codes is on a separate MySQL instance (imartap).
-- Integrity enforced in PHP (PromoCode::validate() against imartap).
-- =============================================================================

CREATE TABLE IF NOT EXISTS `cart_promo_codes` (
  `id`               INT           NOT NULL AUTO_INCREMENT,
  `cart_id`          INT           NOT NULL,
  `cart_type`        ENUM('l','no') NOT NULL COMMENT 'l = porachki_l, no = porachki_no',
  `promo_code_id`    INT           NOT NULL COMMENT 'imartap.promo_codes.id — no cross-instance FK',
  `code`             VARCHAR(50)   NOT NULL,
  `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `discount_value`   DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT 'snapshot at apply-time; avoids cross-instance read at recalc',
  `type`             ENUM('percent','fixed','shipping','shipping_percent') NOT NULL,
  `subtype`          ENUM('voucher','coupon') NULL DEFAULT NULL,
  `shipping_cap`     DECIMAL(10,2) NULL DEFAULT NULL,
  `created_at`       VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_cart_promo` (`cart_id`, `cart_type`, `promo_code_id`),
  KEY `idx_promo_code` (`promo_code_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
