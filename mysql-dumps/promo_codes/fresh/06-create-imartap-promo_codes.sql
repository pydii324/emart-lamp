-- =============================================================================
-- 06 — promo_codes (catalog / definition — the imartap master)
-- Target: imartap ONLY. Shared catalog across all sites (bg/ro/gr/al).
-- Run: mysql -D imartap < 06-create-imartap-promo_codes.sql
--
-- Plain SQL, no guards, no prepared statements. NOT idempotent: on a re-run or a
-- non-empty target MySQL raises an error and aborts — that error is the signal.
-- Baseline: a DB with NOTHING promo-related (original pre-migration schema).
-- An imartap that ALREADY has promo_codes is not a fresh target — this file will
-- fail with ERROR 1050 there, by design. Reconcile such a DB by hand.
--
-- Why this is a SEPARATE imartap file (like 07/order_promo_codes):
--   promo_codes is the single source of truth for every promo definition and
--   lives ONLY in imartap — the regional cart/order copies (01/02) store a
--   promo_code_id that points here (no cross-DB FK). It is the id master that
--   07's FK (fk_opc_promo_code_id) references, so it MUST be created BEFORE 07.
--
-- From-0 note: the live regional deploy assumes imartap already has this table
--   (shared catalog, out of scope). A true from-scratch deploy has no imartap
--   catalog yet — hence this file. Definition mirrors the live imartap table.
-- =============================================================================

CREATE TABLE `promo_codes` (
  `id`              INT           NOT NULL AUTO_INCREMENT,
  `code`            VARCHAR(50)   NOT NULL,
  `type`            ENUM('percent','fixed','shipping','shipping_percent') NOT NULL DEFAULT 'percent',
  `subtype`         ENUM('voucher','coupon') NULL DEFAULT NULL COMMENT 'fixed only: NULL/voucher → SKU 5555555, coupon → SKU 7777777',
  `discount_value`  DECIMAL(10,2) NOT NULL,
  `currency`        ENUM('BGN','EUR','ALL','RON') NOT NULL DEFAULT 'BGN' COMMENT 'code currency (ALL = Albanian lek, RON = Romanian leu)',
  `min_subtotal`    DECIMAL(10,2) NOT NULL DEFAULT 0,
  `shipping_cap`    DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'shipping/shipping_percent: max discount, NULL = uncapped',
  `max_uses`        INT           NOT NULL DEFAULT 0 COMMENT '0 = unlimited',
  `times_used`      INT           NOT NULL DEFAULT 0,
  `active`          BOOLEAN       NOT NULL DEFAULT TRUE,
  `stack_group`     TINYINT       NULL DEFAULT NULL COMMENT 'NULL = stacks freely, same number = only 1 from group',
  `expiration_date` VARCHAR(14)   NULL DEFAULT NULL COMMENT 'YYYYMMDDHHmmss, NULL = no expiry',
  `created_at`      VARCHAR(14)   NOT NULL,
  `used_at`         VARCHAR(14)   NULL DEFAULT NULL,
  `source`          ENUM('the-marketer','manual','bulk-import') NOT NULL DEFAULT 'manual',
  `note`            VARCHAR(255)  NULL DEFAULT NULL,
  -- 'all' is the WILDCARD (valid on every region), in live use by the staff
  -- codes (created_by 'Служебен ALL-…'). Do NOT confuse it with 'al' = Albania.
  -- Omitting 'all' here truncates those rows on a live imartap.
  `site`            ENUM('bg','ro','gr','al','all') NOT NULL COMMENT 'bg | ro | gr | al | all = всички региони',
  `created_by`      VARCHAR(255)  NULL DEFAULT NULL,

  PRIMARY KEY (`id`),
  UNIQUE KEY `code` (`code`),
  KEY `idx_active_exp` (`active`, `expiration_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
