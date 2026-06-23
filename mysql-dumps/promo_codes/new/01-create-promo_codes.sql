-- =============================================================================
-- 01 — promo_codes (catalog, imartap only)
-- Target: imartap
-- Idempotent: CREATE TABLE IF NOT EXISTS
-- =============================================================================

USE imartap;

CREATE TABLE IF NOT EXISTS `promo_codes` (
  `id`              INT           NOT NULL AUTO_INCREMENT,
  `code`            VARCHAR(50)   NOT NULL,
  `type`            ENUM('percent','fixed','shipping','shipping_percent') NOT NULL DEFAULT 'percent',
  `subtype`         ENUM('voucher','coupon') NULL DEFAULT NULL COMMENT 'fixed only: NULL/voucher → SKU 5555555, coupon → SKU 7777777',
  `discount_value`  DECIMAL(10,2) NOT NULL,
  `min_subtotal`    DECIMAL(10,2) NOT NULL DEFAULT 0,
  `shipping_cap`    DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'shipping/shipping_percent: max discount лв.; NULL = uncapped',
  `max_uses`        INT           NOT NULL DEFAULT 0 COMMENT '0 = unlimited',
  `times_used`      INT           NOT NULL DEFAULT 0,
  `active`          BOOLEAN       NOT NULL DEFAULT TRUE,
  `stack_group`     TINYINT       NULL DEFAULT NULL COMMENT 'NULL = stacks freely; same number = only 1 from group',
  `expiration_date` VARCHAR(14)   NULL DEFAULT NULL COMMENT 'YYYYMMDDHHmmss; NULL = no expiry',
  `created_at`      VARCHAR(14)   NOT NULL,
  `used_at`         VARCHAR(14)   NULL DEFAULT NULL,
  `source`          ENUM('the-marketer','manual','bulk-import') NOT NULL DEFAULT 'manual',
  `note`            VARCHAR(255)  NULL DEFAULT NULL,
  `site`            ENUM('bg','ro','gr') NOT NULL COMMENT 'bg | ro | gr',
  `created_by`      VARCHAR(255)  NULL DEFAULT NULL,

  PRIMARY KEY (`id`),
  UNIQUE KEY `code` (`code`),
  KEY `idx_active_exp` (`active`, `expiration_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
