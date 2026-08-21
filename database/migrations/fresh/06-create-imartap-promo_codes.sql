-- =============================================================================
-- 06 — promo_codes (catalog / definition — the imartap master)
-- Target: imartap ONLY. Shared catalog across every site (see the `site` ENUM).
-- Run: mysql -D imartap < 06-create-imartap-promo_codes.sql
--
-- Plain SQL, no guards, no prepared statements. NOT idempotent: on a re-run or a
-- non-empty target MySQL raises an error and aborts — that error is the signal.
-- Baseline: a DB with NOTHING promo-related (original pre-migration schema).
-- An imartap that ALREADY has promo_codes is not a fresh target — this file will
-- fail with ERROR 1050 there, by design. Reconcile such a DB by hand.
--
-- Why this is a SEPARATE imartap file (like 07/order_promo_codes):
--   promo_codes is the single source of truth for every promo definition and
--   lives ONLY in imartap — the regional cart/order copies (01/02) store a
--   promo_code_id that points here (no cross-DB FK). It is the id master that
--   07's FK (fk_opc_promo_code_id) references, so it MUST be created BEFORE 07.
--
-- From-0 note: the live regional deploy assumes imartap already has this table
--   (shared catalog, out of scope). A true from-scratch deploy has no imartap
--   catalog yet — hence this file. Definition mirrors the live imartap table.
-- =============================================================================

CREATE TABLE `promo_codes` (
  `id`              INT           NOT NULL AUTO_INCREMENT,
  `code`            VARCHAR(50)   NOT NULL,
  -- 'shipping_percent' intentionally NOT in this ENUM (removed 2026-08-21) — the
  -- application code (lib/PromoCalc.php, lib/PromoCode.php, promo-input.php,
  -- promo-cart-rows.php, the-marketer/promo-codes.php) still fully implements
  -- this type for when it is reintroduced; only the DB-level option is dropped
  -- here. Re-adding it later is a normal ENUM ADD in both this table and
  -- cart_promo_codes (01) — MySQL converts ENUM values by string, so appending
  -- it back at the end is a safe, in-place ALTER.
  `type`            ENUM('percent','fixed','shipping') NOT NULL DEFAULT 'percent',
  `subtype`         ENUM('voucher','coupon') NULL DEFAULT NULL COMMENT 'fixed only: NULL/voucher → SKU 5555555, coupon → SKU 7777777',
  `discount_value`  DECIMAL(10,2) NOT NULL,
  -- One currency per region — see PromoCode::SITE_CURRENCY, which is the single
  -- source of truth for the site → currency mapping. Every value here MUST also
  -- have a `currency_rates` row (file 09) or PromoCode::toEur() silently falls
  -- back to rate 1.0 and a `fixed` code is deducted at its face value in EUR.
  -- The first four are the original set and the rest were APPENDED. Keep adding
  -- at the end: MySQL converts ENUM values by string, so a mid-list insert does
  -- not remap anything, but it forces ALGORITHM=COPY (a full table rebuild)
  -- where an append is in-place and LOCK=NONE.
  -- No region maps to BGN any more (Bulgaria is euro-only — PromoCode::
  -- SITE_CURRENCY['bg'] is 'EUR') and BGN is no longer the base either; EUR is,
  -- both here and in currency_rates. The value stays because old codes and every
  -- past order snapshot reference it — BGN is now just a legally fixed currency
  -- like any other, at 1/1.95583 EUR.
  `currency`        ENUM('BGN','EUR','ALL','RON',
                         'CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD','RUB','SEK','TRY','UAH','USD','CAD')
                    NOT NULL DEFAULT 'EUR' COMMENT 'code currency (ALL = Albanian lek, RON = Romanian leu, MDL = Moldovan leu, MKD = Macedonian denar, RSD = Serbian dinar)',
  `min_subtotal`    DECIMAL(10,2) NOT NULL DEFAULT 0,
  `shipping_cap`    DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'shipping only for now: max discount, NULL = uncapped (see the shipping_percent note above)',
  `max_uses`        INT           NOT NULL DEFAULT 0 COMMENT '0 = unlimited',
  `times_used`      INT           NOT NULL DEFAULT 0,
  `active`          BOOLEAN       NOT NULL DEFAULT TRUE,
  `stack_group`     TINYINT       NULL DEFAULT NULL COMMENT 'NULL = stacks freely, same number = only 1 from group',
  `expiration_date` VARCHAR(14)   NULL DEFAULT NULL COMMENT 'YYYYMMDDHHmmss, NULL = no expiry',
  `created_at`      VARCHAR(14)   NOT NULL,
  `used_at`         VARCHAR(14)   NULL DEFAULT NULL,
  `source`          ENUM('the-marketer','manual','bulk-import') NOT NULL DEFAULT 'manual',
  `note`            VARCHAR(255)  NULL DEFAULT NULL,
  -- One region per code — there is no wildcard. 'all' USED to mean "valid
  -- everywhere"; it was retired (see deploy/08-retire-site-all-wildcard.sql) and
  -- lib/PromoCode.php now matches the region exactly. 'al' = Albania is a real
  -- region, one letter away from the dead wildcard — do not confuse them.
  -- This file is CREATE TABLE IF NOT EXISTS, so it is a noop on the live
  -- imartap, where `site` stays the pre-migration VARCHAR(10) NULL and enforces
  -- nothing; there the fail-closed PHP check is the only guard.
  --
  -- The list MUST stay byte-identical to PromoCode::SITES (same values, same
  -- order) — adding a region means this ENUM first, then that const, then a
  -- PromoCode::SITE_CURRENCY entry (the-marketer's generator refuses a region
  -- with no currency). 'en' / 'biz' / 'org' are storefronts, not countries:
  -- they carry no national currency and are mapped to EUR. 'co' is Canada (CAD)
  -- — not the .co TLD and not Colombia.
  -- bg/ro/gr/al stay first — they are the original four and the 33 new regions
  -- are APPENDED, never interleaved. Same reason as `currency` above: a mid-list
  -- insert is safe for the data but forces a full table copy.
  -- Live instances already on the four-region ENUM: see
  -- deploy/10-extend-site-and-currency-enums.sql.
  `site`            ENUM('bg','ro','gr','al',
                         'en','md','at','cz','de','es','hr','hu','it','pl','si','sk','cy','uk','us','co',
                         'be','dk','ee','fi','fr','lt','lv','nl','pt','se','mk','rs','ua','tr','ru',
                         'biz','org')
                    NOT NULL COMMENT 'регионът, за който важи кодът — по един на код, без wildcard (виж PromoCode::SITES)',
  `created_by`      VARCHAR(255)  NULL DEFAULT NULL,

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_code_site` (`code`, `site`),
  KEY `idx_active_exp` (`active`, `expiration_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
