-- =============================================================================
-- order_promo_codes — pivot за финализирани употреби на codes (FRESH INSTALL)
-- =============================================================================
-- FK към promo_codes.id — изпълни 01-create-promo_codes.sql преди този файл.
--
-- Insert-ва се от PromoCode::markUsed() при потвърдена поръчка.
-- Източник на истината за usage history; глобалният брояч promo_codes.times_used
-- се increment-ва паралелно при markUsed().
--
-- Разлика спрямо историческия old/03: колоната used_by_employeeId е вградена
-- директно (в old/ пътя тя идва от отделния 11-add-used-by-employee.sql).
--
-- Идемпотентен: CREATE TABLE IF NOT EXISTS.
-- =============================================================================

USE imartap;

CREATE TABLE IF NOT EXISTS `order_promo_codes` (
  `id`                 INT           NOT NULL AUTO_INCREMENT,
  `order_id`           INT           NOT NULL COMMENT 'porachki.porachki_id',
  `promo_code_id`      INT           NOT NULL,
  `klienti_id`         INT           NOT NULL DEFAULT 0 COMMENT '0 = гост',
  `discount_applied`   DECIMAL(10,2) NOT NULL,
  `used_by_employeeId` INT           NULL DEFAULT NULL COMMENT 'Employee who used the code (admin/backoffice app; legacy obshti_kodove.potrebitel). Storefront оставя NULL.',
  `created_at`         VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_order_promo` (`order_id`, `promo_code_id`),
  KEY `idx_klienti` (`klienti_id`, `promo_code_id`),
  CONSTRAINT `fk_opc_promo` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
