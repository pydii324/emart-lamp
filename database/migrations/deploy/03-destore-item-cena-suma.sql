-- =============================================================================
-- DEPLOY 03 — Convert it_cena_suma VIRTUAL → normal stored FLOAT (plain SQL)
-- =============================================================================
-- Run MANUALLY, per database. Plain statements — no SET @ddl / PREPARE guards,
-- no re-run safety. Run each block ONCE against the intended DB.
--
-- ASSUMED STARTING STATE (== state after deploy/01): the item tables have
--     it_cena       FLOAT  stored   (base unit price)
--     it_suma       FLOAT  stored   (base line total)
--     it_cena_suma  FLOAT  VIRTUAL  (= ROUND(it_cena * item_br, 2))  -- converted here
--
-- END STATE:
--     it_cena_suma  FLOAT  stored   (= ROUND(it_cena * item_br, 2), backfilled)
--                                    -- from now on written by the cart/finalize PHP
--                                    -- (it_cena_suma == it_suma at every write site)
--
-- WHERE TO RUN:
--   • Section A (`item`)             → imartap AND every regional DB
--   • Section B (`item_l`,`item_no`) → regional DBs ONLY (imartap has no item_l/item_no)
--
-- The backfill UPDATE is fully derived (it_cena_suma = ROUND(it_cena*item_br,2)),
-- so it is safe to re-run at any time to repair NULL/stale rows.
--
-- Ship this together with the PHP change (cart writers, podavam_za.php,
-- lib/db-switch.php now write it_cena_suma explicitly).
-- =============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- Section A — `item`   (run on imartap AND every regional DB)
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE `item` DROP COLUMN `it_cena_suma`;
ALTER TABLE `item` ADD COLUMN `it_cena_suma` FLOAT NULL DEFAULT NULL
  COMMENT 'Unit base price x quantity (it_cena * item_br) — stored, written by cart/finalize'
  AFTER `it_suma`;
UPDATE `item` SET `it_cena_suma` = ROUND(COALESCE(`it_cena`,0) * `item_br`, 2);


-- ═══════════════════════════════════════════════════════════════════════════
-- Section B — `item_l` + `item_no`   (regional DBs ONLY)
-- ═══════════════════════════════════════════════════════════════════════════

-- ── item_l ──
ALTER TABLE `item_l` DROP COLUMN `it_cena_suma`;
ALTER TABLE `item_l` ADD COLUMN `it_cena_suma` FLOAT NULL DEFAULT NULL
  COMMENT 'Unit base price x quantity (it_cena * item_br) — stored, written by cart/finalize'
  AFTER `it_suma`;
UPDATE `item_l` SET `it_cena_suma` = ROUND(COALESCE(`it_cena`,0) * `item_br`, 2);

-- ── item_no ──
ALTER TABLE `item_no` DROP COLUMN `it_cena_suma`;
ALTER TABLE `item_no` ADD COLUMN `it_cena_suma` FLOAT NULL DEFAULT NULL
  COMMENT 'Unit base price x quantity (it_cena * item_br) — stored, written by cart/finalize'
  AFTER `it_suma`;
UPDATE `item_no` SET `it_cena_suma` = ROUND(COALESCE(`it_cena`,0) * `item_br`, 2);
