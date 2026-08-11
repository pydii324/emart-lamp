-- =============================================================================
-- 01 — currency_rates: re-base from BGN to EUR
-- Target: imartap ONLY (currency_rates lives there alone).
-- Run: mysql -D imartap < 01-rebase-currency-rates-to-eur.sql
--
-- Plain SQL, no guards. NOT idempotent on purpose: a second run fails on the
-- first statement with ERROR 1054 (unknown column 'rate_to_bgn'), because the
-- column it renames is already gone. That error is the signal — 00-preflight
-- check B tells you which state the instance is in BEFORE you start.
--
-- ⚠ MUST run before 02 (which inserts `rate_to_eur` rows) and before 04/05/06
--   go live, since the PHP reads rate_to_eur.
--
-- WHAT CHANGES:
--     rate_to_bgn  →  rate_to_eur        (1 unit of X = N euro)
--     every value  ÷  1.95583            (the irrevocable adoption rate)
--     EUR: 1.95583 → 1.00000000, is_fixed = 1   (the base, self)
--     BGN: 1.00000 → 0.51129188, is_fixed = 1   (now an ordinary fixed currency)
--
-- WHY: the cart used to be priced in BGN, so currency_rates stored rate_to_bgn
-- and lib/PromoCode.php normalised every promo money-field into leva at the
-- catalog read boundary. The storefront is priced in EUR now — Bulgaria is
-- euro-only — so the base moves with it (PromoCode::toEur / ratesToEur).
--
-- BGN is NOT dropped. No region authors in it any more (PromoCode::
-- SITE_CURRENCY['bg'] is 'EUR'), but legacy BGN promo codes and every past order
-- snapshot still carry `currency = 'BGN'`, and they only convert if the row is
-- there. A code for 19.56 BGN keeps deducting exactly 10.00 EUR.
--
-- ⚠ WHAT THIS FILE DOES **NOT** DO — read README.md §"Какво този set НЕ прави".
--   It re-bases the RATE TABLE only. Not one stored money amount is touched, so
--   promo figures written while the cart was in leva read 1.95583× too large
--   afterwards. That is a separate data migration with its own cut-over question.
-- =============================================================================


-- ── 1. Rename the column ─────────────────────────────────────────────────────
-- Done as CHANGE-then-UPDATE rather than pasting 18 literals, because a CHANGE
-- cannot carry an expression and the arithmetic below must apply to whatever is
-- actually in the table — on any instance that has run the rate cron even once,
-- the floating rates have drifted away from the shipped placeholders and those
-- real values must be preserved.
ALTER TABLE `currency_rates`
  CHANGE `rate_to_bgn` `rate_to_eur` DECIMAL(18,8) NOT NULL
    COMMENT '1 unit of `currency` = rate_to_eur EUR';


-- ── 2. Divide every rate through ─────────────────────────────────────────────
-- ROUND to 8dp to match the column scale exactly; MySQL would round implicitly
-- to the same result, but then the intent is not visible in the file.
UPDATE `currency_rates`
   SET `rate_to_eur` = ROUND(`rate_to_eur` / 1.95583, 8);


-- ── 3. Pin the two legally fixed anchors ─────────────────────────────────────
-- Step 2 already produced these numbers arithmetically; restating them as
-- literals makes the base exactly 1 rather than 1.00000000-ish from a division,
-- records what the fixed pair IS instead of leaving it implied, and repairs an
-- instance where either row had been hand-edited.
--
-- is_fixed = 1 is what keeps scripts/update-currency-rates.php away from them:
-- the BNB feed is EUR-based now and does not list BGN at all, so an unflagged
-- BGN row would log `WARN: provider had no rate for BGN` forever.
UPDATE `currency_rates`
   SET `rate_to_eur` = 1.00000000, `is_fixed` = 1, `source` = 'fixed'
 WHERE `currency` = 'EUR';

UPDATE `currency_rates`
   SET `rate_to_eur` = 0.51129188, `is_fixed` = 1, `source` = 'fixed'
 WHERE `currency` = 'BGN';


-- The `currency` column DEFAULT also moves BGN → EUR, but that is not done here:
-- files 04 / 05 / 06 re-declare those columns with DEFAULT 'EUR' as part of
-- widening the ENUM, so a separate ALTER … SET DEFAULT would be redundant.
