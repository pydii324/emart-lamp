-- =============================================================================
-- 10 — order_promo_codes (finalized order pivot)
-- Target: imartap AND regional DBs
-- Idempotent: CREATE TABLE IF NOT EXISTS + FK guards
--
-- Schema is identical on both instances; FK constraints are added only on
-- imartap (DATABASE()='imartap') where both referenced tables live:
--   porachki.porachki_id  — order master
--   promo_codes.id        — promo catalog
--
-- Regional DBs run the same file but DATABASE()≠'imartap' → FK steps are no-ops.
-- Write order: imartap first (order_id originates there), then regional copy.
-- promo_codes.times_used is still incremented in parallel by updateTimesUsed().
-- =============================================================================

CREATE TABLE IF NOT EXISTS `order_promo_codes` (
  `id`                 INT           NOT NULL AUTO_INCREMENT,
  `order_id`           INT           NOT NULL COMMENT 'porachki.porachki_id',
  `promo_code_id`      INT           NOT NULL COMMENT 'imartap.promo_codes.id',
  `klienti_id`         INT           NOT NULL DEFAULT 0 COMMENT '0 = guest',
  `discount_applied`   DECIMAL(10,2) NOT NULL,
  `used_by_employeeId` INT           NULL DEFAULT NULL COMMENT 'backoffice app; storefront leaves NULL',
  `created_at`         VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_order_promo` (`order_id`, `promo_code_id`),
  KEY `idx_klienti` (`klienti_id`, `promo_code_id`),
  KEY `idx_promo_code` (`promo_code_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── FK constraints (imartap only) ────────────────────────────────────────────
-- Regional DBs: these SET/PREPARE blocks are no-ops (DATABASE() ≠ 'imartap').

SET @ddl := (SELECT IF(
  DATABASE() = 'imartap'
  AND NOT EXISTS(
    SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'order_promo_codes'
      AND CONSTRAINT_NAME = 'fk_opc_order_id'),
  'ALTER TABLE `order_promo_codes` ADD CONSTRAINT `fk_opc_order_id`'
  ' FOREIGN KEY (`order_id`) REFERENCES `porachki` (`porachki_id`)'
  ' ON DELETE RESTRICT ON UPDATE RESTRICT',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  DATABASE() = 'imartap'
  AND NOT EXISTS(
    SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'order_promo_codes'
      AND CONSTRAINT_NAME = 'fk_opc_promo_code_id'),
  'ALTER TABLE `order_promo_codes` ADD CONSTRAINT `fk_opc_promo_code_id`'
  ' FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`)'
  ' ON DELETE RESTRICT ON UPDATE RESTRICT',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
