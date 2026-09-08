-- =============================================================================
-- 02 — order_promo_codes (regional order history)
-- Target: regional DB (Albania). imartap catalog is shared / out of scope.
-- Run: mysql -D <regional_db> < 02-create-order_promo_codes.sql
--
-- Plain SQL, no guards, no prepared statements. NOT idempotent: on a re-run or a
-- non-empty target MySQL raises an error and aborts — that error is the signal.
-- Baseline: a DB with NOTHING promo-related (original pre-migration schema).
--
-- promo_code_id -> imartap.promo_codes.id: no cross-DB FK (intentional).
-- =============================================================================

CREATE TABLE `order_promo_codes` (
  `id`                 INT           NOT NULL AUTO_INCREMENT,
  `order_id`           INT           NOT NULL COMMENT 'porachki.porachki_id',
  `promo_code_id`      INT           NOT NULL COMMENT 'imartap.promo_codes.id (no cross-DB FK)',
  `klienti_id`         INT           NOT NULL DEFAULT '0' COMMENT '0 = guest',
  -- In `currency` below, like every other amount here: a region has one
  -- currency, and its codes, cart and orders are all priced in it. Nothing is
  -- converted — see the CURRENCY note in citte/lib/PromoCode.php.
  `discount_applied`   DECIMAL(10,2) NOT NULL COMMENT 'in `currency` — the amount actually deducted from the order',
  -- Mirrors promo_codes.currency (fresh/06) — keep the two lists identical and
  -- in the same order, and APPEND new currencies rather than inserting them
  -- mid-list: MySQL converts ENUM values by string so nothing is remapped
  -- either way, but a mid-list insert forces ALGORITHM=COPY (full rebuild)
  -- where an append is in-place and LOCK=NONE.
  `currency`           ENUM('BGN','EUR','ALL','RON',
                            'CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD','RUB','SEK','TRY','UAH','USD','CAD')
                       NOT NULL DEFAULT 'EUR' COMMENT 'snapshot of promo_codes.currency at order-finalize — the unit of discount_applied',
  `used_by_employeeId` INT           DEFAULT NULL COMMENT 'admin/backoffice app — storefront leaves NULL',
  `created_at`         VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_order_promo` (`order_id`,`promo_code_id`),
  KEY `idx_klienti` (`klienti_id`,`promo_code_id`),
  KEY `idx_promo_code` (`promo_code_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
