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
  -- Every amount in this row is in `currency` below — the region's single
  -- currency, which is also what its cart (item_l/item_no) is priced in. Nothing
  -- is ever converted; see the CURRENCY note in citte/lib/PromoCode.php.
  --
  -- COMPUTED: what was actually deducted, and what prices the negative promo SKU
  -- row in item_l/item_no.
  `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT '0.00' COMMENT 'in `currency` — 0 for shipping types, real deduction for percent/fixed',
  -- SNAPSHOT of promo_codes.discount_value, byte-for-byte as the catalog holds
  -- it. (percent / shipping_percent store a %, which has no currency.)
  `discount_value`   DECIMAL(10,2) NOT NULL DEFAULT '0.00' COMMENT 'promo_codes.discount_value at apply-time, in `currency` — unconverted',
  -- Mirrors promo_codes.currency (fresh/06) — keep the two lists identical and
  -- in the same order, and APPEND new currencies rather than inserting them
  -- mid-list: MySQL converts ENUM values by string so nothing is remapped
  -- either way, but a mid-list insert forces ALGORITHM=COPY (full rebuild)
  -- where an append is in-place and LOCK=NONE.
  `currency`         ENUM('BGN','EUR','ALL','RON',
                          'CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD','RUB','SEK','TRY','UAH','USD','CAD')
                     NOT NULL DEFAULT 'EUR' COMMENT 'snapshot of promo_codes.currency at apply-time — the unit of EVERY amount in this row',
  -- 'shipping_percent' intentionally NOT in this ENUM — see the note on the
  -- `type` column in 06-create-imartap-promo_codes.sql.
  `type`             ENUM('percent','fixed','shipping') NOT NULL,
  `subtype`          ENUM('voucher','coupon') DEFAULT NULL,
  `shipping_cap`     DECIMAL(10,2) DEFAULT NULL COMMENT 'promo_codes.shipping_cap, in `currency` — flat cap on the discount, NULL = uncapped',
  `created_at`       VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_cart_promo` (`cart_id`,`cart_type`,`promo_code_id`),
  KEY `idx_promo_code` (`promo_code_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
