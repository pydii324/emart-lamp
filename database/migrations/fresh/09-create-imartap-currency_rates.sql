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
-- `currency` (promo_codes.currency). The cart is priced in EUR, so
-- lib/PromoCode.php converts BGN/RON/… → EUR at the catalog read boundary using
-- these rates (PromoCode::toEur / ratesToEur). Base currency = EUR.
--
--   rate_to_eur : 1 unit of `currency` = rate_to_eur EUR.
--   is_fixed=1  : legally fixed / irrevocable (EUR self, BGN adoption rate).
--                 The rate-updater (scripts/update-currency-rates.php) MUST skip
--                 these — only is_fixed=0 (floating) rows are refreshed from BNB.
--
-- BASE CURRENCY IS EUR, NOT BGN. It used to be BGN (column `rate_to_bgn`) back
-- when the cart was priced in leva. Bulgaria is euro-only now, the cart is EUR,
-- and BGN became just another currency — a legally fixed one, at 1 BGN =
-- 1/1.95583 EUR = 0.51129188. It keeps its row because legacy promo codes and
-- every past order snapshot still reference BGN. An instance created before the
-- switch is migrated by mysql-dumps/deploy/11-rebase-currency-rates-to-eur.sql,
-- which renames the column and divides every rate by 1.95583.
--
-- The BNB feed is itself EUR-based, so the refresh job now stores REVERSERATE
-- verbatim instead of multiplying it by 1.95583 — one less conversion hop.
--
-- NOTE: `promo_codes.currency` (file 06) ships the same 18 currencies seeded
-- below, so every one of them is authorable on a code without a further
-- migration. Adding a NEW currency means extending that ENUM first (in 06 AND in
-- the two pivot copies, 01/02 — 07 on imartap), then a row here, then the
-- PromoCode::SITE_CURRENCY entry that points a region at it.
-- =============================================================================

CREATE TABLE `currency_rates` (
  `currency`    CHAR(3)        NOT NULL                COMMENT 'ISO 4217: EUR (base), BGN, RON, ...',
  `rate_to_eur` DECIMAL(18,8)  NOT NULL                COMMENT '1 unit of `currency` = rate_to_eur EUR',
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
--   EUR — base currency (self), rate 1.0. Fixed, never fetched.
--   BGN — irrevocable adoption rate, 1 BGN = 1/1.95583 EUR = 0.51129188. Fixed.
--         No region authors in BGN any more (Bulgaria is euro-only —
--         PromoCode::SITE_CURRENCY['bg'] is 'EUR'), but the row must stay: legacy
--         BGN codes and every past order snapshot still reference the value.
--   RON — floating (Romania). Placeholder ~ recent value; refreshed by the BNB job.
--   ALL — Albanian lek. Floating, but BNB does NOT publish it → source 'manual';
--         the BNB job leaves it untouched. Placeholder ~ 1 lek; update by hand or
--         point the fetch at a provider that carries lek (e.g. Bank of Albania).
--
-- The 14 rows after ALL back the non-euro regions added alongside them (see
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
INSERT INTO `currency_rates` (`currency`, `rate_to_eur`, `is_fixed`, `source`, `updated_at`) VALUES
  ('EUR', 1.00000000, 1, 'fixed',  NULL),
  ('BGN', 0.51129188, 1, 'fixed',  NULL),
  ('RON', 0.20119336, 0, 'bnb',    NULL),
  ('ALL', 0.01002132, 0, 'manual', NULL),
  ('CZK', 0.04049432, 0, 'bnb',    NULL),
  ('DKK', 0.13406073, 0, 'bnb',    NULL),
  ('GBP', 1.17085841, 0, 'bnb',    NULL),
  ('HUF', 0.00255646, 0, 'bnb',    NULL),
  ('MDL', 0.05061790, 0, 'manual', NULL),
  ('MKD', 0.01625908, 0, 'manual', NULL),
  ('PLN', 0.23519427, 0, 'bnb',    NULL),
  ('RSD', 0.00853857, 0, 'manual', NULL),
  ('RUB', 0.01048148, 0, 'bnb',    NULL),
  ('SEK', 0.08947608, 0, 'bnb',    NULL),
  ('TRY', 0.02403072, 0, 'bnb',    NULL),
  ('UAH', 0.02147426, 0, 'bnb',    NULL),
  ('USD', 0.85897036, 0, 'bnb',    NULL),
  ('CAD', 0.64934069, 0, 'bnb',    NULL);
