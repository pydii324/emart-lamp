-- =============================================================================
-- DEPLOY 05 — Drop it_cena_suma (redundant duplicate of it_suma)
-- =============================================================================
-- it_cena_suma held ROUND(it_cena * item_br, 2) and was written to the SAME value
-- as it_suma at every write site (cart writers v_case*.php, order finalize
-- podavam_za.php, promo negative rows lib/db-switch.php). It is redundant with
-- it_suma and is being removed. Post-promo prices live in it_cena_new/it_suma_new
-- (ERP / storefront), the per-line delta in discount_applied.
--
-- Plain SQL — no SET @ddl / PREPARE guards, no re-run safety. If the column is
-- already gone the ALTER throws; that error is the migration signal. Run each
-- block ONCE against the intended DB.
--
-- WHERE TO RUN:
--   • Section A (`item`)             → imartap AND every regional DB
--   • Section B (`item_l`,`item_no`) → regional DBs ONLY (imartap has no item_l/item_no)
--
-- Ship together with the PHP change that stops writing it_cena_suma.
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- Section A — `item`   (run on imartap AND every regional DB)
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE `item` DROP COLUMN `it_cena_suma`;

-- ═══════════════════════════════════════════════════════════════════════════
-- Section B — `item_l` + `item_no`   (regional DBs ONLY)
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE `item_l` DROP COLUMN `it_cena_suma`;
ALTER TABLE `item_no` DROP COLUMN `it_cena_suma`;
