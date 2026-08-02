-- =============================================================================
-- 04 — porachki promo columns (order + cart headers)
-- Target: ALL DBs — regional (porachki/porachki_l/porachki_no) AND imartap
--         (porachki master). Run against each DB that holds a porachki* table.
-- Run:  mysql -D <regional_db> < 04-add-porachki-promo-columns.sql
--       mysql -D imartap       < 04-add-porachki-promo-columns.sql
--
--   pordost_coupon_discount : porachki, porachki_l, porachki_no
--   promo_fixed_discount    : porachki_l, porachki_no ONLY (mini-cart net display)
--
-- Plain SQL, no guards, no prepared statements. NOT idempotent: on a re-run or a
-- non-empty target MySQL raises an error and aborts — that error is the signal.
-- Baseline: a DB with NOTHING promo-related (original pre-migration schema).
-- =============================================================================

-- ── pordost_coupon_discount : porachki / porachki_l / porachki_no ─────────────
ALTER TABLE `porachki`    ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT '0.00' COMMENT 'shipping-coupon discount on delivery cost';
ALTER TABLE `porachki_l`  ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT '0.00' COMMENT 'shipping-coupon discount on delivery cost';
ALTER TABLE `porachki_no` ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT '0.00' COMMENT 'shipping-coupon discount on delivery cost';

-- ── promo_fixed_discount : porachki_l / porachki_no ONLY ─────────────────────
ALTER TABLE `porachki_l`  ADD COLUMN `promo_fixed_discount` DECIMAL(10,2) NOT NULL DEFAULT '0.00' COMMENT 'Order-level fixed/voucher promo total on the cart (mini-cart net display)';
ALTER TABLE `porachki_no` ADD COLUMN `promo_fixed_discount` DECIMAL(10,2) NOT NULL DEFAULT '0.00' COMMENT 'Order-level fixed/voucher promo total on the cart (mini-cart net display)';
