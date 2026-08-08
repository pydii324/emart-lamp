-- =============================================================================
-- 06 — cart_promo_codes: currency → 18 currencies
-- Target: EVERY regional DB ONLY. Repeat once per region.
-- Run: mysql -D <regional_db> < 06-extend-cart_promo_codes-currency.sql
--
-- ⚠ NOT on imartap — imartap has no cart_promo_codes and the file would abort
--   with ERROR 1146. The cart pivot is regional-only by design: it holds the
--   codes applied to a live cart, and carts live next to the region's own
--   porachki_l / porachki_no.
--
-- Plain SQL. MODIFY is naturally re-runnable — it re-declares the same type — so
-- this file does not fail loudly on a second run; 00-preflight check D is the
-- state signal instead.
--
-- WHY: cart_promo_codes.currency snapshots promo_codes.currency at apply-time.
-- Its ENUM must match promo_codes' or the snapshot truncates the moment a
-- shopper applies a code in one of the 14 new currencies.
--
-- There is no `site` column here — the region is implied by which DB you are in.
--
-- The DEFAULT moves BGN → EUR with it, and the list is APPENDED to rather than
-- reordered — see 04's header for why that matters.
-- =============================================================================

ALTER TABLE `cart_promo_codes`
  MODIFY `currency` ENUM('BGN','EUR','ALL','RON',
                         'CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD','RUB','SEK','TRY','UAH','USD','CAD')
                    NOT NULL DEFAULT 'EUR'
                    COMMENT 'snapshot of promo_codes.currency at apply-time';
