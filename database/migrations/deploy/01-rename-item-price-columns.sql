-- =============================================================================
-- DEPLOY 01 — Rename item price columns to Svetlyo's schema (plain SQL)
-- =============================================================================
-- Run MANUALLY, per database. Plain statements — no SET @ddl / PREPARE guards,
-- no re-run safety. Run each block ONCE against the intended DB.
--
-- ASSUMED STARTING STATE (the state dev / old-path staging was in before this
-- change): the item tables have
--     it_cena_baza  FLOAT  stored   (base unit price)
--     it_suma_baza  FLOAT  stored   (base line total)
--     it_cena       FLOAT  VIRTUAL  (old post-promo)     -- will be dropped
--     it_suma       FLOAT  VIRTUAL  (old post-promo)     -- will be dropped
--     it_cena_suma  FLOAT  VIRTUAL  (refs it_cena_baza)  -- will be dropped
--     discount_applied DECIMAL(10,2)
--
-- END STATE (== current dev schema):
--     it_cena       FLOAT  stored   (base, renamed from it_cena_baza)
--     it_suma       FLOAT  stored   (base, renamed from it_suma_baza)
--     it_cena_new   FLOAT  stored    )  post-promo, WRITTEN BY THE STOREFRONT
--     it_suma_new   FLOAT  stored    )  (CartItems::applyItemDiscounts(), podavam_za.php)
--     item_br_new   INT    stored    \  post-promo, WRITTEN BY SVETLYO'S ERP
--     promot_new    VARCHAR(20) st.  /  (not derived by us)
--     it_cena_suma  FLOAT  VIRTUAL  (= ROUND(it_cena * item_br, 2))
--
-- WHERE TO RUN:
--   • Section A (`item`)          → imartap AND every regional DB
--   • Section B (`item_l`,`item_no`) → regional DBs ONLY (imartap has no item_l/item_no)
--
-- NOTE on the `_new` columns: if Svetlyo's ERP has ALREADY added `item_br_new`/
-- `promot_new` on the target DB, the matching ADD COLUMN below will fail with
-- "Duplicate column". That is expected — just skip the statements for columns
-- that already exist. `it_cena_new`/`it_suma_new` are storefront-owned now.
--
-- Ship this together with the PHP change (cart writers/readers now use
-- it_cena/it_suma). Running it without the PHP update breaks the cart.
-- =============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- Section A — `item`   (run on imartap AND every regional DB)
-- ═══════════════════════════════════════════════════════════════════════════

-- drop old virtual columns first (they reference the *_baza columns)
ALTER TABLE `item` DROP COLUMN `it_cena_suma`;
ALTER TABLE `item` DROP COLUMN `it_cena`;
ALTER TABLE `item` DROP COLUMN `it_suma`;

-- rename the stored base columns
ALTER TABLE `item` CHANGE COLUMN `it_cena_baza` `it_cena` FLOAT NULL DEFAULT NULL AFTER `item_br`;
ALTER TABLE `item` CHANGE COLUMN `it_suma_baza` `it_suma` FLOAT NULL DEFAULT NULL AFTER `it_cena`;

-- Post-promo columns: it_cena_new/it_suma_new are storefront-owned; item_br_new/
-- promot_new stay Svetlyo's ERP-owned (SKIP any that already exist)
ALTER TABLE `item` ADD COLUMN `it_cena_new` FLOAT       NULL DEFAULT NULL COMMENT 'Final unit price after promo — written by storefront (it_suma_new / item_br)';
ALTER TABLE `item` ADD COLUMN `it_suma_new` FLOAT       NULL DEFAULT NULL COMMENT 'Final line total after promo — written by storefront (it_suma − discount_applied)';
ALTER TABLE `item` ADD COLUMN `item_br_new` INT         NULL DEFAULT NULL COMMENT 'Final quantity after promo — written by ERP';
ALTER TABLE `item` ADD COLUMN `promot_new`  VARCHAR(20) NULL DEFAULT NULL COMMENT 'Promo marker after promo — written by ERP';

-- base line-total helper (re-pointed to the renamed it_cena)
ALTER TABLE `item` ADD COLUMN `it_cena_suma` FLOAT
  GENERATED ALWAYS AS (ROUND(COALESCE(`it_cena`,0) * `item_br`, 2)) VIRTUAL
  COMMENT 'Unit base price x quantity (it_cena * item_br)' AFTER `it_suma`;


-- ═══════════════════════════════════════════════════════════════════════════
-- Section B — `item_l` + `item_no`   (regional DBs ONLY)
-- ═══════════════════════════════════════════════════════════════════════════

-- ── item_l ──
ALTER TABLE `item_l` DROP COLUMN `it_cena_suma`;
ALTER TABLE `item_l` DROP COLUMN `it_cena`;
ALTER TABLE `item_l` DROP COLUMN `it_suma`;
ALTER TABLE `item_l` CHANGE COLUMN `it_cena_baza` `it_cena` FLOAT NULL DEFAULT NULL AFTER `item_br`;
ALTER TABLE `item_l` CHANGE COLUMN `it_suma_baza` `it_suma` FLOAT NULL DEFAULT NULL AFTER `it_cena`;
ALTER TABLE `item_l` ADD COLUMN `it_cena_new` FLOAT       NULL DEFAULT NULL COMMENT 'Final unit price after promo — written by storefront (it_suma_new / item_br)';
ALTER TABLE `item_l` ADD COLUMN `it_suma_new` FLOAT       NULL DEFAULT NULL COMMENT 'Final line total after promo — written by storefront (it_suma − discount_applied)';
ALTER TABLE `item_l` ADD COLUMN `item_br_new` INT         NULL DEFAULT NULL COMMENT 'Final quantity after promo — written by ERP';
ALTER TABLE `item_l` ADD COLUMN `promot_new`  VARCHAR(20) NULL DEFAULT NULL COMMENT 'Promo marker after promo — written by ERP';
ALTER TABLE `item_l` ADD COLUMN `it_cena_suma` FLOAT
  GENERATED ALWAYS AS (ROUND(COALESCE(`it_cena`,0) * `item_br`, 2)) VIRTUAL
  COMMENT 'Unit base price x quantity (it_cena * item_br)' AFTER `it_suma`;

-- ── item_no ──
ALTER TABLE `item_no` DROP COLUMN `it_cena_suma`;
ALTER TABLE `item_no` DROP COLUMN `it_cena`;
ALTER TABLE `item_no` DROP COLUMN `it_suma`;
ALTER TABLE `item_no` CHANGE COLUMN `it_cena_baza` `it_cena` FLOAT NULL DEFAULT NULL AFTER `item_br`;
ALTER TABLE `item_no` CHANGE COLUMN `it_suma_baza` `it_suma` FLOAT NULL DEFAULT NULL AFTER `it_cena`;
ALTER TABLE `item_no` ADD COLUMN `it_cena_new` FLOAT       NULL DEFAULT NULL COMMENT 'Final unit price after promo — written by storefront (it_suma_new / item_br)';
ALTER TABLE `item_no` ADD COLUMN `it_suma_new` FLOAT       NULL DEFAULT NULL COMMENT 'Final line total after promo — written by storefront (it_suma − discount_applied)';
ALTER TABLE `item_no` ADD COLUMN `item_br_new` INT         NULL DEFAULT NULL COMMENT 'Final quantity after promo — written by ERP';
ALTER TABLE `item_no` ADD COLUMN `promot_new`  VARCHAR(20) NULL DEFAULT NULL COMMENT 'Promo marker after promo — written by ERP';
ALTER TABLE `item_no` ADD COLUMN `it_cena_suma` FLOAT
  GENERATED ALWAYS AS (ROUND(COALESCE(`it_cena`,0) * `item_br`, 2)) VIRTUAL
  COMMENT 'Unit base price x quantity (it_cena * item_br)' AFTER `it_suma`;
