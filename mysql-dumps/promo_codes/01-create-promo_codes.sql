-- =============================================================================
-- promo_codes — главна таблица за промо кодове
-- =============================================================================
-- Заменя legacy таблиците `loyality_points` и `obshti_kodove` (които остават
-- read-only за reference).
-- Виж promo-codes-master-plan.md за пълно design rationale.
--
-- Ред на изпълнение: 01 → 02 → 03 → 04 → 05 → 06 → 07
-- =============================================================================

USE imartap;

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS `promo_codes`;

CREATE TABLE `promo_codes` (
  `id`                INT           NOT NULL AUTO_INCREMENT,
  `code`              VARCHAR(50)   NOT NULL,
  `type`              ENUM('percent','fixed','shipping') NOT NULL DEFAULT 'percent',

  -- Стойност
  `discount_value`    DECIMAL(10,2) NOT NULL,
  `voucher_remainer`  DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'само за fixed — бюджет, намалява при употреба',

  -- Ограничения
  `min_subtotal`      DECIMAL(10,2) NOT NULL DEFAULT 0,
  `shipping_cap`      DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'само за shipping (NULL = без cap)',
  `max_uses`          INT           NOT NULL DEFAULT 0 COMMENT '0 = безлимит',
  `times_used`        INT           NOT NULL DEFAULT 0 COMMENT 'брояч на употреби; ++ при markUsed()',

  -- Поведение
  `active`            BOOLEAN       NOT NULL DEFAULT TRUE,
  `stack_group`       TINYINT       NULL DEFAULT NULL COMMENT 'NULL = комбинира се с всичко',

  -- Дати (всички VARCHAR(14) YYYYMMDDHHmmss)
  `expiration_date`   VARCHAR(14)   NULL DEFAULT NULL,
  `created_at`        VARCHAR(14)   NOT NULL,
  `used_at`           VARCHAR(14)   NULL DEFAULT NULL COMMENT 'last-used; update-ва се при markUsed()',

  -- Произход / метадата
  `source`            ENUM('the-marketer','manual','bulk-import') NOT NULL DEFAULT 'manual',
  `note`              VARCHAR(255)  NULL DEFAULT NULL COMMENT 'бивш komentar',
  `site`              VARCHAR(10)   NULL DEFAULT NULL COMMENT 'бивш sait — bg/ro/gr/all',
  `created_by`        VARCHAR(255)  NULL DEFAULT NULL COMMENT 'бивш ot_kade — free-form audit',

  PRIMARY KEY (`id`),
  UNIQUE KEY `code` (`code`),
  KEY `idx_active_exp` (`active`, `expiration_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
