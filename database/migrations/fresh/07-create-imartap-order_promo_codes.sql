-- =============================================================================
-- 07 — order_promo_codes (imartap copy — the id master)
-- Target: imartap ONLY. Companion to 02 (regional copy).
-- Run: mysql -D imartap < 07-create-imartap-order_promo_codes.sql
--
-- Plain SQL, no guards, no prepared statements. NOT idempotent: on a re-run or a
-- non-empty target MySQL raises an error and aborts — that error is the signal.
-- Baseline: a DB with NOTHING promo-related (original pre-migration schema).
-- For an already-migrated DB whose order_promo_codes exists WITHOUT the FKs, use
-- the guarded ../../deploy/04-order_promo_codes-porachki-fk.sql instead.
--
-- Why a SEPARATE imartap file (the ONE difference vs the regional 02):
--   PromoCode::finalize() writes imartap FIRST (autoincrement master), reads the
--   id back, then mirrors it to the regional copy (lib/PromoCode.php:304-333).
--   Both referenced masters live in imartap — porachki (order) and promo_codes
--   (catalog) — so the referential links are enforced HERE with real FKs.
--   On the regional DB (02) order_id / promo_code_id are copies of imartap ids →
--   NO FK there. Same table, imartap-only foreign keys.
--
-- Prerequisite: `promo_codes` (created by 06, run it first) and `porachki` (order
-- master, from the core schema) both exist in imartap. FK add fails if imartap has
-- orphan history rows (order_id absent from porachki) — a fresh install is empty,
-- so this is clean.
-- =============================================================================

CREATE TABLE `order_promo_codes` (
  `id`                 INT           NOT NULL AUTO_INCREMENT,
  `order_id`           INT           NOT NULL COMMENT 'porachki.porachki_id',
  `promo_code_id`      INT           NOT NULL COMMENT 'promo_codes.id',
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
  KEY `idx_promo_code` (`promo_code_id`),

  CONSTRAINT `fk_opc_order_id`
    FOREIGN KEY (`order_id`)      REFERENCES `porachki` (`porachki_id`)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT `fk_opc_promo_code_id`
    FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`)
    ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
