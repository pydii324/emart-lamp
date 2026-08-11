-- =============================================================================
-- 05 — catalog promo SKU seed (Microinvest negative rows)
-- Target: regional DB (Albania). catalog table lives in the regional DB.
-- Run: mysql -D <regional_db> < 05-seed-catalog-promo-skus.sql
--
-- Plain SQL, no guards. Baseline: a DB with NOTHING promo-related.
--
-- ⚠️ THE ONE FILE IN THIS SET WITH NO NATURAL RE-RUN PROTECTION. `catalog` has no
-- UNIQUE KEY on `cat_no`, so a second run does NOT error — it silently inserts a
-- duplicate of all four SKUs. Run it exactly once per regional DB. If you do run
-- it twice, undo with:
--     DELETE FROM `catalog` WHERE `cat_no` IN ('5555555','6666666','7777777','8888888');
-- and re-run this file. (Everything else in the set is protected: promo_codes.code
-- is UNIQUE, currency_rates.currency is the PK, the rest are bare CREATE TABLE.)
--
--   5555555 voucher/coupon      6666666 free shipping
--   7777777 coupon              8888888 percent discount
-- All cena = 0 (price carried by the promo row itself).
-- vidimost = 0 and p_acti = 0: the SKU must NOT be listable/orderable as a normal
-- product — the storefront guards on vidimost=0 so a shopper cannot add / bump the
-- quantity of a promo line by hand (see the memory / promo-codes docs).
-- NOTE: miarka is 'бр.' as in BG. Adjust the unit label if Albania differs.
--
-- SET NAMES utf8mb4 below is REQUIRED: without it a latin1 client connection
-- double-encodes the Cyrillic and stores mojibake (this is exactly how the live
-- BG catalog got corrupted). Keep it, or load with --default-character-set=utf8mb4.
-- =============================================================================

SET NAMES utf8mb4;

INSERT INTO `catalog` (`cat_no`, `ime`, `miarka`, `cena`, `vidimost`, `p_acti`, `nnindex`) VALUES
  ('5555555', 'Промо ваучер/купон',       'бр.', 0.00, 0, 0, 'promo-5555555'),
  ('6666666', 'Промо безплатна доставка', 'бр.', 0.00, 0, 0, 'promo-6666666'),
  ('7777777', 'Промо купон',              'бр.', 0.00, 0, 0, 'promo-7777777'),
  ('8888888', 'Промо процентна отстъпка', 'бр.', 0.00, 0, 0, 'promo-8888888');
