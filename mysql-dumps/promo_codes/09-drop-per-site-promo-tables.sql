-- Single-source consolidation: promo tables live ONLY in imartap.
-- Drops promo_codes / cart_promo_codes / order_promo_codes from per-site DBs
-- (inmarta, iimarta, almarta, ...). PHP now reads/writes them on the imartap
-- connection (lib/db-switch.php), so the per-site copies are dead.
--
-- SAFETY: every DROP is guarded by DATABASE() <> 'imartap', so running this
-- against imartap is a no-op and the 16k production codes are never touched.
-- DROP TABLE IF EXISTS makes it idempotent. Order: child pivots first, then
-- promo_codes (FK targets).

SET FOREIGN_KEY_CHECKS = 0;

SET @ddl := IF(DATABASE() <> 'imartap', 'DROP TABLE IF EXISTS `cart_promo_codes`', 'DO 0');
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := IF(DATABASE() <> 'imartap', 'DROP TABLE IF EXISTS `order_promo_codes`', 'DO 0');
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := IF(DATABASE() <> 'imartap', 'DROP TABLE IF EXISTS `promo_codes`', 'DO 0');
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET FOREIGN_KEY_CHECKS = 1;
