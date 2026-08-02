-- =============================================================================
-- DEPLOY 04 — order_promo_codes: ensure table + link it to porachki (imartap)
-- =============================================================================
-- Run against EVERY database (imartap + every regional DB). Idempotent &
-- guarded (unlike deploy/01-03) ON PURPOSE: the foreign keys must exist ONLY on
-- imartap, and a re-run / an already-present FK must be a no-op — plain
-- ADD CONSTRAINT cannot express either safely.
--
-- WHY imartap-only FKs:
--   PromoCode::finalize() writes imartap FIRST (autoincrement master) and mirrors
--   the id to the regional copy (see lib/PromoCode.php:304-333). The order master
--   `porachki` and the promo catalog `promo_codes` both live in imartap, so the
--   referential link is enforceable there. On a regional DB `order_id` /
--   `promo_code_id` are copies of imartap-generated ids → NO local FK (would point
--   at a regional porachki row that may not exist / is written after). This is the
--   ONLY schema difference between the imartap and the regional instance.
--
-- Mirrors the intent of new/10-create-order_promo_codes.sql. FK guards key off the
-- REFERENCED table (not the constraint name) so a pre-existing differently-named
-- promo FK (dev ships `fk_opc_promo`) is detected and NOT duplicated.
-- =============================================================================


-- ── Table (all DBs) — no-op where it already exists ──────────────────────────
CREATE TABLE IF NOT EXISTS `order_promo_codes` (
  `id`                 INT           NOT NULL AUTO_INCREMENT,
  `order_id`           INT           NOT NULL COMMENT 'porachki.porachki_id',
  `promo_code_id`      INT           NOT NULL COMMENT 'imartap.promo_codes.id',
  `klienti_id`         INT           NOT NULL DEFAULT 0 COMMENT '0 = guest',
  `discount_applied`   DECIMAL(10,2) NOT NULL,
  `currency`           ENUM('BGN','EUR') NOT NULL DEFAULT 'BGN' COMMENT 'snapshot of promo_codes.currency at order-finalize',
  `used_by_employeeId` INT           NULL DEFAULT NULL COMMENT 'backoffice app; storefront leaves NULL',
  `created_at`         VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_order_promo` (`order_id`, `promo_code_id`),
  KEY `idx_klienti` (`klienti_id`, `promo_code_id`),
  KEY `idx_promo_code` (`promo_code_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ── FK order_id → porachki.porachki_id  (imartap ONLY) ───────────────────────
SET @ddl := (SELECT IF(
  DATABASE() = 'imartap'
  AND NOT EXISTS(
    SELECT 1 FROM information_schema.KEY_COLUMN_USAGE
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME    = 'order_promo_codes'
      AND COLUMN_NAME   = 'order_id'
      AND REFERENCED_TABLE_NAME = 'porachki'),
  'ALTER TABLE `order_promo_codes` ADD CONSTRAINT `fk_opc_order_id`'
  ' FOREIGN KEY (`order_id`) REFERENCES `porachki` (`porachki_id`)'
  ' ON DELETE RESTRICT ON UPDATE RESTRICT',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;


-- ── FK promo_code_id → promo_codes.id  (imartap ONLY) ────────────────────────
-- Guard on the referenced table so an existing `fk_opc_promo` is NOT re-added.
SET @ddl := (SELECT IF(
  DATABASE() = 'imartap'
  AND NOT EXISTS(
    SELECT 1 FROM information_schema.KEY_COLUMN_USAGE
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME    = 'order_promo_codes'
      AND COLUMN_NAME   = 'promo_code_id'
      AND REFERENCED_TABLE_NAME = 'promo_codes'),
  'ALTER TABLE `order_promo_codes` ADD CONSTRAINT `fk_opc_promo_code_id`'
  ' FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`)'
  ' ON DELETE RESTRICT ON UPDATE RESTRICT',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
