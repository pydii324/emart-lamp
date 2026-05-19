CREATE TABLE IF NOT EXISTS `cart_promo_codes` (
    `id`               INT            AUTO_INCREMENT PRIMARY KEY,
    `cart_id`          INT            NOT NULL,
    `cart_type`        ENUM('l','no') NOT NULL,               -- 'l' = porachki_l (logged-in), 'no' = porachki_no (guest)
    `promo_code_id`    INT            NOT NULL,
    `code`             VARCHAR(50)    NOT NULL,
    `discount_applied` DECIMAL(10,2)  NOT NULL DEFAULT 0.00,  -- 0 for type=shipping; actual deduction for percent/fixed
    `type`             ENUM('percent','fixed','shipping') NOT NULL,
    `shipping_cap`     DECIMAL(10,2)  NULL DEFAULT NULL,      -- only for type=shipping
    `created_at`       TIMESTAMP      DEFAULT CURRENT_TIMESTAMP,

    UNIQUE KEY `uq_cart_promo` (`cart_id`, `cart_type`, `promo_code_id`),
    CONSTRAINT `fk_cpc_promo` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
