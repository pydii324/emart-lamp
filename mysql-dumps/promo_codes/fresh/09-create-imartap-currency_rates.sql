-- =============================================================================
-- 09 — currency_rates (FX rate table — the imartap master)
-- Target: imartap ONLY. Shared across every site (see promo_codes.site, file 06).
-- Run: mysql -D imartap < 09-create-imartap-currency_rates.sql
--
-- Plain SQL, no guards, no prepared statements. NOT idempotent: on a re-run or a
-- non-empty target MySQL raises an error and aborts — that error is the signal.
-- Baseline: a DB with NOTHING promo-related (original pre-migration schema).
-- The seed INSERT is a single statement: `currency` is the PRIMARY KEY, so a
-- re-run fails with ERROR 1062 rather than overwriting a live job-updated rate.
--
-- Purpose (issue #610): promo money-fields are authored in the code's own
-- `currency` (promo_codes.currency). The cart is always priced in BGN, so
-- lib/PromoCode.php converts EUR/RON/… → BGN at the catalog read boundary using
-- these rates (PromoCode::toBgn / ratesToBgn). Base currency = BGN.
--
--   rate_to_bgn : 1 unit of `currency` = rate_to_bgn BGN.
--   is_fixed=1  : legally fixed / irrevocable (BGN self, EUR adoption rate).
--                 The rate-updater (scripts/update-currency-rates.php) MUST skip
--                 these — only is_fixed=0 (floating) rows are refreshed from BNB.
--
-- NOTE: `promo_codes.currency` (file 06) ships the same 17 currencies seeded
-- below, so every one of them is authorable on a code without a further
-- migration. Adding a NEW currency means extending that ENUM first (in 06 AND in
-- the two pivot copies, 01/02 — 07 on imartap), then a row here, then the
-- PromoCode::SITE_CURRENCY entry that points a region at it.
-- =============================================================================

CREATE TABLE `currency_rates` (
  `currency`    CHAR(3)        NOT NULL                COMMENT 'ISO 4217: BGN (base), EUR, RON, ...',
  `rate_to_bgn` DECIMAL(18,8)  NOT NULL                COMMENT '1 unit of `currency` = rate_to_bgn BGN',
  `is_fixed`    TINYINT(1)     NOT NULL DEFAULT 0      COMMENT '1 = legally fixed (irrevocable) — updater MUST skip',
  `source`      VARCHAR(16)    NOT NULL DEFAULT 'manual' COMMENT 'fixed | bnb | manual',
  `updated_at`  DATETIME       NULL     DEFAULT NULL   COMMENT 'last refresh, NULL until first job run',
  PRIMARY KEY (`currency`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Every rate below except BGN/EUR is a PLACEHOLDER of the right order of
-- magnitude, not a quote. source = 'bnb' rows are overwritten on the first job
-- run; source = 'manual' rows are NOT and must be set by hand before a code is
-- authored in them, or a `fixed` discount converts at a stale rate.
--
--   BGN — base currency (self). Fixed.
--   EUR — irrevocable BGN adoption rate 1 EUR = 1.95583 BGN. Fixed, never fetched.
--   RON — floating (Romania). Placeholder ~ recent value; refreshed by the BNB job.
--   ALL — Albanian lek. Floating, but BNB does NOT publish it → source 'manual';
--         the BNB job leaves it untouched. Placeholder ~ 1 lek; update by hand or
--         point the fetch at a provider that carries lek (e.g. Bank of Albania).
--
-- The 13 rows after ALL back the non-euro regions added alongside them (see
-- PromoCode::SITE_CURRENCY). source = 'bnb' is claimed for the currencies the
-- BNB daily fixing lists; the job is data-driven (it refreshes every
-- is_fixed = 0 AND source = 'bnb' row) so no code change is needed for them, and
-- a currency BNB happens to drop is only logged as `WARN: provider had no rate
-- for …` and left at its last value — it is never zeroed.
--
--   MDL / MKD / RSD — Moldovan leu, Macedonian denar, Serbian dinar. BNB does
--         not publish these (same situation as ALL) → source 'manual'. MKD and
--         RSD are de-facto euro-pegged, so their placeholders drift slowly; MDL
--         floats and wants a real feed before any MDL code is authored.
INSERT INTO `currency_rates` (`currency`, `rate_to_bgn`, `is_fixed`, `source`, `updated_at`) VALUES
  ('BGN', 1.00000000, 1, 'fixed',  NULL),
  ('EUR', 1.95583000, 1, 'fixed',  NULL),
  ('RON', 0.39350000, 0, 'bnb',    NULL),
  ('ALL', 0.01960000, 0, 'manual', NULL),
  ('CZK', 0.07920000, 0, 'bnb',    NULL),
  ('DKK', 0.26220000, 0, 'bnb',    NULL),
  ('GBP', 2.29000000, 0, 'bnb',    NULL),
  ('HUF', 0.00500000, 0, 'bnb',    NULL),
  ('MDL', 0.09900000, 0, 'manual', NULL),
  ('MKD', 0.03180000, 0, 'manual', NULL),
  ('PLN', 0.46000000, 0, 'bnb',    NULL),
  ('RSD', 0.01670000, 0, 'manual', NULL),
  ('RUB', 0.02050000, 0, 'bnb',    NULL),
  ('SEK', 0.17500000, 0, 'bnb',    NULL),
  ('TRY', 0.04700000, 0, 'bnb',    NULL),
  ('UAH', 0.04200000, 0, 'bnb',    NULL),
  ('USD', 1.68000000, 0, 'bnb',    NULL);
