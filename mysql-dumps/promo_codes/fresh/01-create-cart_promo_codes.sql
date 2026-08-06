-- =============================================================================
-- 01 — cart_promo_codes (regional cart pivot)
-- Target: regional DB (Albania). imartap catalog is shared / out of scope.
-- Run: mysql -D <regional_db> < 01-create-cart_promo_codes.sql
--
-- Plain SQL, no guards, no prepared statements. NOT idempotent: on a re-run or a
-- non-empty target MySQL raises an error and aborts — that error is the signal.
-- Baseline: a DB with NOTHING promo-related (original pre-migration schema).
--
-- promo_code_id -> imartap.promo_codes.id: no cross-DB FK (intentional).
-- =============================================================================

CREATE TABLE `cart_promo_codes` (
  `id`               INT           NOT NULL AUTO_INCREMENT,
  `cart_id`          INT           NOT NULL,
  `cart_type`        ENUM('l','no') NOT NULL COMMENT 'l = porachki_l (logged-in), no = porachki_no (guest)',
  `promo_code_id`    INT           NOT NULL COMMENT 'imartap.promo_codes.id (no cross-DB FK)',
  `code`             VARCHAR(50)   NOT NULL,
  `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT '0.00' COMMENT '0 for shipping types — real deduction for percent/fixed',
  `discount_value`   DECIMAL(10,2) NOT NULL DEFAULT '0.00' COMMENT 'snapshot of promo_codes.discount_value at apply-time',
  -- Mirrors promo_codes.currency (fresh/06) — keep the two lists identical, in
  -- the same order (ENUM stores an ordinal; new currencies are APPENDED only).
  `currency`         ENUM('BGN','EUR','ALL','RON',
                          'CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD','RUB','SEK','TRY','UAH','USD')
                     NOT NULL DEFAULT 'BGN' COMMENT 'snapshot of promo_codes.currency at apply-time',
  `type`             ENUM('percent','fixed','shipping','shipping_percent') NOT NULL,
  `subtype`          ENUM('voucher','coupon') DEFAULT NULL,
  `shipping_cap`     DECIMAL(10,2) DEFAULT NULL COMMENT 'shipping/shipping_percent only (flat cap on the discount)',
  `created_at`       VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_cart_promo` (`cart_id`,`cart_type`,`promo_code_id`),
  KEY `idx_promo_code` (`promo_code_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
