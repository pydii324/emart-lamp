-- =============================================================================
-- 02 — currency_rates: rows for the 14 new currencies
-- Target: imartap ONLY. Run AFTER 01.
-- Run: mysql -D imartap < 02-seed-new-currency-rates.sql
--
-- Plain SQL, no guards. NOT idempotent: `currency` is the PRIMARY KEY, so a
-- re-run fails with ERROR 1062 instead of overwriting a rate the cron has
-- already refreshed. That error is the signal.
--
-- ⚠ ATOMIC. This is ONE multi-row INSERT: if even one of the 14 currencies
--   already has a row, the statement fails and NONE of them land. 00-preflight
--   check I lists exactly that — run it first, and drop the colliding literals
--   from the list below if it returns anything.
--
-- ⚠ 01 MUST have run. This names `rate_to_eur`; on a table still carrying
--   `rate_to_bgn` it fails with ERROR 1054. The values are EUR-based — inserted
--   into a leva-based table they would be off by 1.95583.
--
-- WHY: the 33 new regions in file 04 need currencies (PromoCode::SITE_CURRENCY
-- maps cz→CZK, pl→PLN, uk→GBP, us→USD, co→CAD, …), and PromoCode::toEur() falls
-- back to rate 1.0 for a currency with no row here — a `fixed` HUF code would
-- then be deducted at its face value in euro. The rows must exist before any
-- code is authored in those currencies.
--
-- BGN is not in this list and needs no row added: 01 already re-based its
-- existing row to 0.51129188 and flagged it fixed.
--
-- Every value below is a PLACEHOLDER of the right order of magnitude, not a quote:
--   source = 'bnb'    → scripts/update-currency-rates.php overwrites it on the
--                       next run. The job is data-driven (it refreshes every
--                       is_fixed = 0 AND source = 'bnb' row), so no code change
--                       is needed for them; a currency the BNB feed happens to
--                       omit is only logged as `WARN: provider had no rate for …`
--                       and left at its last value — never zeroed.
--   source = 'manual' → BNB does not publish it (same situation as ALL). NOT
--                       refreshed by anything. MKD and RSD are de-facto
--                       euro-pegged so their placeholders drift slowly; MDL
--                       floats and wants a real rate set by hand before an MDL
--                       code is authored.
-- =============================================================================

INSERT INTO `currency_rates` (`currency`, `rate_to_eur`, `is_fixed`, `source`, `updated_at`) VALUES
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
