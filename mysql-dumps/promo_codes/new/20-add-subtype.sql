-- Migration 20: add subtype column to distinguish voucher vs coupon within type='fixed'.
-- NULL = voucher (default / unknown) → cat_no 5555555; 'coupon' → cat_no 7777777.
--
-- Run against: imartap (promo_codes) + every regional DB (cart_promo_codes).
-- Idempotent via IF NOT EXISTS.

-- imartap
ALTER TABLE promo_codes
    ADD COLUMN IF NOT EXISTS `subtype` ENUM('voucher','coupon') NULL DEFAULT NULL AFTER `type`;

-- regional DBs (cart_promo_codes is next to the cart, not in imartap)
ALTER TABLE cart_promo_codes
    ADD COLUMN IF NOT EXISTS `subtype` ENUM('voucher','coupon') NULL DEFAULT NULL AFTER `type`;
