-- =============================================================================
-- 05 — order_promo_codes: currency → 18 currencies
-- Target: imartap AND every regional DB. Run once per DB that has the table.
-- Run:  mysql -D imartap        < 05-extend-order_promo_codes-currency.sql
--       mysql -D <regional_db>  < 05-extend-order_promo_codes-currency.sql
--
-- Plain SQL. MODIFY is naturally re-runnable — it re-declares the same type — so
-- this file does not fail loudly on a second run; 00-preflight check D is the
-- state signal instead.
--
-- WHY BOTH TARGETS: PromoCode::finalize() writes the imartap copy FIRST (it is
-- the autoincrement master), reads the id back, then mirrors the row into the
-- regional copy (lib/PromoCode.php:304-333). Both copies snapshot
-- promo_codes.currency at finalize, so both ENUMs must match promo_codes' or the
-- snapshot is truncated the moment an order uses a code in a new currency.
--
-- The DEFAULT moves BGN → EUR with it: the cart is priced in euro now, and a
-- future INSERT that forgets the column must not silently claim leva.
--
-- The list is APPENDED to, never reordered — see 04's header for why that
-- matters (in-place ALTER vs full table copy, and comparable COLUMN_TYPE).
-- =============================================================================

ALTER TABLE `order_promo_codes`
  MODIFY `currency` ENUM('BGN','EUR','ALL','RON',
                         'CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD','RUB','SEK','TRY','UAH','USD','CAD')
                    NOT NULL DEFAULT 'EUR'
                    COMMENT 'snapshot of promo_codes.currency at order-finalize';
