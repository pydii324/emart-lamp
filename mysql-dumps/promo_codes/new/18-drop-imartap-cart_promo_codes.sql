-- issue #610 Q1: cart_promo_codes is now a REGIONAL pivot (see
-- 14-create-cart_promo_codes-regional.sql) — it must NOT live in imartap.
-- The legacy imartap copy (created by 02-create-cart_promo_codes.sql in the
-- historical/fresh path) is dead: promo_recalc / PromoCode read & write the
-- regional table. This drops the imartap copy.
--
-- SAFETY:
--  - cart_promo_codes is TRANSIENT (cleared on every order finalize), so the
--    imartap copy holds at most in-flight carts — no historical data is lost.
--  - Guarded by DATABASE() = 'imartap' → NO-OP against regional DBs, so the LIVE
--    regional table is never touched. Run order: AFTER 14-create-..-regional.
--  - DROP TABLE IF EXISTS → idempotent. cart_promo_codes is the FK child
--    (references promo_codes), so dropping it leaves the promo_codes catalog intact.
--
-- NOTE: order_promo_codes is usage HISTORY; moving it imartap -> regional needs a
-- data migration first, so it is intentionally NOT dropped here.
SET @ddl := IF(DATABASE() = 'imartap', 'DROP TABLE IF EXISTS `cart_promo_codes`', 'DO 0');
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
