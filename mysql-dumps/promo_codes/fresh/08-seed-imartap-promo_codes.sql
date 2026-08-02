-- =============================================================================
-- 08 — promo_codes seed (one reference row per promo TYPE)
-- Target: imartap ONLY. promo_codes is the shared catalog (see 06).
-- Run: mysql -D imartap < 08-seed-imartap-promo_codes.sql   (AFTER 06)
--
-- Plain SQL, no guards. Baseline: a DB with NOTHING promo-related. `promo_codes.code`
-- is UNIQUE, so a re-run (or a collision with an operator-created code of the same
-- name) fails with ERROR 1062 instead of silently duplicating — that error is the
-- signal. Nothing here ever overwrites an existing row.
--
-- One example code for every distinct promo behaviour the storefront supports.
-- These are ACTIVE, working codes (so a fresh install can be QA'd end-to-end).
-- To ship a catalog WITHOUT live sample codes: set `active` = 0 below, or delete
-- them after verification (see Reset at the bottom of README.md).
--
-- Type → behaviour → catalog SKU (05 seed) → PromoCalc path (lib/PromoCalc.php):
--   percent           % off subtotal, best-only          SKU 8888888   (discount_value = %)
--   fixed / voucher   flat amount, burned on use         SKU 5555555   (discount_value = amount)
--   fixed / coupon    flat amount, burned on use         SKU 7777777   (discount_value = amount)
--   shipping (full)   whole shipping free, cap NULL      SKU 6666666   (discount_value unused → 0)
--   shipping (capped) up to shipping_cap off shipping    SKU 6666666   (discount_value unused → 0)
--   shipping_percent  % of full shipping, optional cap   —             (discount_value = %)
--
-- Catalog money-fields are authored in the code's own `currency`; lib/PromoCode.php
-- converts them to the BGN cart at read time via currency_rates (EUR ×1.95583 fixed;
-- BGN passthrough; ALL/lek ×manual rate). Set `currency` per code to 'BGN', 'EUR'
-- or 'ALL'. Codes 1-6 below are EUR examples (site = 'al', Albania); code 7 is an
-- 'ALL' (Albanian lek) example for lek testing. discount_value is monetary only for
-- `fixed`; percent / shipping_percent hold a %, which is never converted.
-- =============================================================================

SET NAMES utf8mb4;

--   1) PERCENT10     percent           — 10% off the cart subtotal (highest-percent-wins)
--   2) VOUCHER5      fixed / voucher   — 5.00 flat off subtotal (SKU 5555555)
--   3) COUPON5       fixed / coupon    — 5.00 flat off subtotal (SKU 7777777)
--   4) FREESHIP      shipping          — whole shipping free, uncapped (SKU 6666666)
--   5) SHIPCAP3      shipping          — up to 3.00 off shipping (SKU 6666666)
--   6) SHIPPCT50     shipping_percent  — 50% of full shipping, uncapped
--   7) VOUCHER500ALL fixed / voucher   — 500 lek off subtotal (SKU 5555555); priced in
--                                        lek → converts to BGN via currency_rates['ALL']
--                                        (500 * 0.0196 ≈ 9.80 BGN)
INSERT INTO `promo_codes`
  (`code`, `type`, `subtype`, `discount_value`, `currency`, `min_subtotal`, `shipping_cap`, `max_uses`, `active`, `expiration_date`, `created_at`, `source`, `note`, `site`, `created_by`) VALUES
  ('PERCENT10',     'percent',          NULL,      10.00, 'EUR', 0.00, NULL, 0, 1, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'Example: 10% off cart subtotal (SKU 8888888)',   'al', 'fresh-seed'),
  ('VOUCHER5',      'fixed',            'voucher',  5.00, 'EUR', 0.00, NULL, 0, 1, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'Example: 5.00 fixed voucher (SKU 5555555)',      'al', 'fresh-seed'),
  ('COUPON5',       'fixed',            'coupon',   5.00, 'EUR', 0.00, NULL, 0, 1, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'Example: 5.00 fixed coupon (SKU 7777777)',       'al', 'fresh-seed'),
  ('FREESHIP',      'shipping',         NULL,       0.00, 'EUR', 0.00, NULL, 0, 1, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'Example: free shipping, uncapped (SKU 6666666)', 'al', 'fresh-seed'),
  ('SHIPCAP3',      'shipping',         NULL,       0.00, 'EUR', 0.00, 3.00, 0, 1, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'Example: up to 3.00 off shipping (SKU 6666666)', 'al', 'fresh-seed'),
  ('SHIPPCT50',     'shipping_percent', NULL,      50.00, 'EUR', 0.00, NULL, 0, 1, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'Example: 50% off shipping, uncapped',            'al', 'fresh-seed'),
  ('VOUCHER500ALL', 'fixed',            'voucher', 500.00, 'ALL', 0.00, NULL, 0, 1, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'Example: 500 lek fixed voucher (SKU 5555555)',  'al', 'fresh-seed');
