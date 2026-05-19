-- =============================================================================
-- cart_promo_codes — pivot за приложени в количка codes
-- =============================================================================
-- FK към promo_codes.id — изпълни 01-create-promo_codes.sql преди този файл.
--
-- Изтрива се при финализиране на поръчка (виж PromoCode::finalizeForOrder()).
-- =============================================================================

USE imartap;

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS `cart_promo_codes`;

CREATE TABLE `cart_promo_codes` (
  `id`               INT           NOT NULL AUTO_INCREMENT,
  `cart_id`          INT           NOT NULL,
  `cart_type`        ENUM('l','no') NOT NULL COMMENT "'l' = porachki_l (logged-in), 'no' = porachki_no (guest)",
  `promo_code_id`    INT           NOT NULL,
  `code`             VARCHAR(50)   NOT NULL,
  `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '0 за type=shipping; реална deduction за percent/fixed',
  `type`             ENUM('percent','fixed','shipping') NOT NULL,
  `shipping_cap`     DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'само за type=shipping',
  `created_at`       VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_cart_promo` (`cart_id`, `cart_type`, `promo_code_id`),
  CONSTRAINT `fk_cpc_promo` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
