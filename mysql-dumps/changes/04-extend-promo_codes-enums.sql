-- =============================================================================
-- 04 — promo_codes: site → 37 regions, currency → 18 currencies
-- Target: imartap ONLY (promo_codes is the shared catalog).
-- Run: mysql -D imartap --default-character-set=utf8mb4 < 04-extend-promo_codes-enums.sql
--
-- ⚠ 03 MUST have run first. Without it, any `site` value the new ENUM lacks
--   (the retired 'all' wildcard, a typo the old VARCHAR accepted) is truncated
--   to '' by this conversion — file 07 check C is what catches that afterwards.
--
-- Plain SQL. MODIFY is naturally re-runnable — it just re-declares the same
-- type — so unlike 01/02 this file does not fail loudly on a second run. The
-- fail-fast signal here is 00-preflight checks C and D instead.
--
-- SET NAMES utf8mb4 is REQUIRED: the `site` COMMENT below is Cyrillic and a
-- latin1 client connection double-encodes it into mojibake in the schema.
--
-- WHY: the storefront region list grew from 4 to 37 (PromoCode::SITES) and each
-- new region needs a currency (PromoCode::SITE_CURRENCY: cz→CZK, pl→PLN,
-- uk→GBP, us→USD, co→CAD, …), so `currency` grows from 4 values to 18. A region
-- outside this ENUM cannot be written at all; one outside PromoCode::SITES can
-- never be redeemed. The two lists must stay byte-identical.
--
-- TWO THINGS THIS FILE DELIBERATELY DOES:
--
--  1. It APPENDS to both ENUMs, never reorders them. 'bg','ro','gr','al' and
--     'BGN','EUR','ALL','RON' keep their original positions; the 33 regions and
--     14 currencies go after them. This is about COST, not corruption: MySQL
--     converts an ENUM column by the value's STRING, so a mid-list insert would
--     keep every row correct — but it forces ALGORITHM=COPY (a full table
--     rebuild under a metadata lock) where a pure append is in-place and
--     LOCK=NONE. Appending also keeps the declared order identical across
--     instances, which is what lets file 07 compare COLUMN_TYPE at all.
--
--  2. It makes `site` NULLable, unlike fresh/06 which declares it NOT NULL.
--     fresh/06 targets a virgin DB with no legacy rows, so NOT NULL is free;
--     here file 03 parks unconvertible values on NULL and needs somewhere to put
--     them. NULL matches no region, which is what those rows already were.
--
-- No ALGORITHM/LOCK hint on purpose: appending ENUM values is in-place on MySQL
-- 8, but NOT NULL → NULL rebuilds the table anyway, so let the server pick the
-- best it can. promo_codes is a small catalog — this is seconds, not minutes.
-- =============================================================================

SET NAMES utf8mb4;

ALTER TABLE `promo_codes`
  MODIFY `currency` ENUM('BGN','EUR','ALL','RON',
                         'CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD','RUB','SEK','TRY','UAH','USD','CAD')
                    NOT NULL DEFAULT 'EUR'
                    COMMENT 'code currency (ALL = Albanian lek, RON = Romanian leu, MDL = Moldovan leu, MKD = Macedonian denar, RSD = Serbian dinar)',
  MODIFY `site`     ENUM('bg','ro','gr','al',
                         'en','md','at','cz','de','es','hr','hu','it','pl','si','sk','cy','uk','us','co',
                         'be','dk','ee','fi','fr','lt','lv','nl','pt','se','mk','rs','ua','tr','ru',
                         'biz','org')
                    NULL DEFAULT NULL
                    COMMENT 'регионът, за който важи кодът — по един на код, без wildcard (виж PromoCode::SITES). NULL = архивен ред, не се осребрява никъде';
