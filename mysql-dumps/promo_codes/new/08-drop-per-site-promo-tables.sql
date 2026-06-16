-- Single-source consolidation for the CATALOG only: `promo_codes` lives ONLY in
-- imartap. The pivots (`cart_promo_codes`, `order_promo_codes`) were MOVED to the
-- per-site/regional DBs (issue #610, Q1) and are therefore NO LONGER dropped
-- here — see 14-create-cart_promo_codes-regional.sql / 15-create-order_promo_codes-regional.sql.
--
-- This script now drops only the dead per-site copy of `promo_codes`.
--
-- SAFETY: the DROP is guarded by DATABASE() <> 'imartap', so running this
-- against imartap is a no-op and the production codes are never touched.
-- DROP TABLE IF EXISTS makes it idempotent. FOREIGN_KEY_CHECKS is disabled so a
-- legacy regional cart_promo_codes FK (from a pre-consolidation install) cannot
-- block the drop.

SET FOREIGN_KEY_CHECKS = 0;

SET @ddl := IF(DATABASE() <> 'imartap', 'DROP TABLE IF EXISTS `promo_codes`', 'DO 0');
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET FOREIGN_KEY_CHECKS = 1;
