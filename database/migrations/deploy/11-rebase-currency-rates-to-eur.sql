-- =============================================================================
-- DEPLOY 11 — Re-base currency_rates from BGN to EUR
-- =============================================================================
-- Run MANUALLY, on imartap ONLY (currency_rates lives there alone).
-- Plain statements — no guards. NOT idempotent on purpose: a second run fails at
-- Section B with ERROR 1054 (unknown column 'rate_to_bgn'), because the column it
-- renames is already gone. That error is the signal, not a problem — see
-- Section A.1, which tells you which state the instance is in BEFORE you start.
--
-- ⚠ RUN THIS BEFORE deploy/10-extend-site-and-currency-enums.sql. Section D.2
--   there inserts `rate_to_eur` rows and fails with ERROR 1054 on a table that
--   has not been re-based yet.
--
-- WHY:
--   The cart used to be priced in BGN, so currency_rates stored `rate_to_bgn`
--   (1 unit of X = N leva) and lib/PromoCode.php converted every promo
--   money-field into leva at the catalog read boundary. The storefront is priced
--   in EUR now — Bulgaria is euro-only — so the base moves with it:
--
--     rate_to_bgn  →  rate_to_eur          (1 unit of X = N euro)
--     every value  ÷  1.95583              (the irrevocable adoption rate)
--     EUR: 1.95583 → 1.00000000, is_fixed = 1   (the base, self)
--     BGN: 1.00000 → 0.51129188, is_fixed = 1   (now an ordinary fixed currency)
--
--   BGN is NOT dropped. No region authors in it any more (PromoCode::
--   SITE_CURRENCY['bg'] is 'EUR'), but legacy BGN promo codes and every past
--   order snapshot still carry `currency = 'BGN'`, and they can only be converted
--   if the row is there.
--
-- ⚠ WHAT THIS FILE DOES **NOT** DO — read before deploying:
--   It re-bases the RATE TABLE only. It does not touch a single stored money
--   amount. Every DECIMAL already written in leva stays a leva figure with no
--   marker saying so:
--     • cart_promo_codes.discount_value  (apply-time snapshot, regional DBs)
--     • order_promo_codes.discount_applied (finalize snapshot, regional+imartap)
--     • porachki.pordost_coupon_discount / promo_fixed_discount
--     • promo_codes.discount_value / min_subtotal / shipping_cap for any row
--       whose `currency` is 'BGN' — those are self-describing and DO convert
--       correctly, because toEur() reads the row's own currency.
--   The first three are the exposure: they are bare numbers in the cart's
--   currency-of-the-day, so a historical order re-read after the switch looks
--   1.95583× too large. Converting them is a data migration with its own
--   cut-over question (which orders predate the switch?) and is deliberately out
--   of scope here — decide it per instance, ideally by freezing promo writes
--   during the switch so there is a clean boundary.
--
-- ORDER vs the other deploy files:
--   … → 08 → 09 → **11** → 10.  11 before 10 (see the warning above); everything
--   else is independent of it.
-- =============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- Section A — preflight (read-only, writes NOTHING)
-- ═══════════════════════════════════════════════════════════════════════════
-- A.1 — which state is this instance in?
--   rate_to_bgn present → not re-based yet, run Section B.
--   rate_to_eur present → already done, STOP (Section B would ERROR 1054).
SELECT
  'A.1 rate column'   AS `check`,
  COLUMN_NAME         AS `column`,
  COLUMN_TYPE         AS `type`,
  IF(COLUMN_NAME = 'rate_to_bgn', 'not re-based yet — run Section B',
                                  'already re-based — STOP, skip Section B') AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'currency_rates'
  AND COLUMN_NAME IN ('rate_to_bgn','rate_to_eur');

-- A.2 — the rates as they stand, with the value each one is about to become.
-- Eyeball two of them: EUR must land on exactly 1.00000000 and BGN on
-- 0.51129188. Anything else means the table was not in leva to begin with.
SELECT
  'A.2 before → after'                   AS `check`,
  `currency`,
  `rate_to_bgn`                          AS `now_in_bgn`,
  ROUND(`rate_to_bgn` / 1.95583, 8)      AS `becomes_in_eur`,
  `is_fixed`,
  `source`
FROM `currency_rates`
ORDER BY `is_fixed` DESC, `currency`;


-- ═══════════════════════════════════════════════════════════════════════════
-- Section B — the re-base
-- ═══════════════════════════════════════════════════════════════════════════
-- B.1 — rename the column and re-base every value in one statement.
--
-- ALTER first, UPDATE second would divide EUR's 1.95583 by 1.95583 to get 1.0 and
-- BGN's 1.0 to get 0.51129188 — the same answer — so the order does not matter
-- mathematically. It is done as CHANGE-then-UPDATE because a CHANGE cannot carry
-- an expression, and doing the arithmetic in SQL (rather than pasting 18 literals)
-- keeps this correct for an instance whose floating rates have already drifted
-- away from the fresh/09 placeholders — which, on anything that has run the cron
-- even once, they have.
ALTER TABLE `currency_rates`
  CHANGE `rate_to_bgn` `rate_to_eur` DECIMAL(18,8) NOT NULL
    COMMENT '1 unit of `currency` = rate_to_eur EUR';

-- B.2 — divide through. ROUND to 8dp to match the column scale exactly; without
-- it MySQL rounds implicitly and the result is the same, but the intent is not
-- visible in the file.
UPDATE `currency_rates`
   SET `rate_to_eur` = ROUND(`rate_to_eur` / 1.95583, 8);

-- B.3 — pin the two legally fixed rows to their exact values.
--
-- B.2 already produced these numbers arithmetically; this restates them as
-- literals so the base is exactly 1, not 1.00000000-ish from a division, and so
-- the file records what the fixed pair IS rather than leaving it implied. It also
-- repairs an instance where someone had hand-edited either row.
--
-- EUR becomes the base (self, 1.0). BGN keeps its row at the irrevocable
-- 1/1.95583 and is flagged fixed so scripts/update-currency-rates.php never
-- fetches it — the BNB feed does not list BGN at all now that it is EUR-based,
-- so an unflagged BGN row would just log a WARN forever.
UPDATE `currency_rates`
   SET `rate_to_eur` = 1.00000000, `is_fixed` = 1, `source` = 'fixed'
 WHERE `currency` = 'EUR';

UPDATE `currency_rates`
   SET `rate_to_eur` = 0.51129188, `is_fixed` = 1, `source` = 'fixed'
 WHERE `currency` = 'BGN';

-- B.4 — the currency column's DEFAULT follows the base. Existing rows are
-- untouched (a DEFAULT only applies to inserts that omit the column); this just
-- stops a future INSERT that forgets `currency` from silently claiming leva.
-- promo_codes is imartap; run the cart/order pair on each regional DB — or skip
-- these three entirely, since deploy/10 re-declares the same columns with the
-- same DEFAULT 'EUR' as part of widening the ENUM.
ALTER TABLE `promo_codes`       ALTER COLUMN `currency` SET DEFAULT 'EUR';
ALTER TABLE `order_promo_codes` ALTER COLUMN `currency` SET DEFAULT 'EUR';
-- ALTER TABLE `cart_promo_codes` ALTER COLUMN `currency` SET DEFAULT 'EUR';   -- regional DBs only


-- ═══════════════════════════════════════════════════════════════════════════
-- Section C — verification (read-only, writes NOTHING)
-- ═══════════════════════════════════════════════════════════════════════════
-- C.1 — the column is renamed and the two fixed anchors are exact.
SELECT
  'C.1 fixed anchors' AS `check`,
  `currency`,
  `rate_to_eur`,
  `is_fixed`,
  CASE
    WHEN `currency` = 'EUR' AND `rate_to_eur` = 1.00000000 AND `is_fixed` = 1 THEN 'OK'
    WHEN `currency` = 'BGN' AND `rate_to_eur` = 0.51129188 AND `is_fixed` = 1 THEN 'OK'
    ELSE 'FAIL — anchor rate or is_fixed flag is wrong'
  END AS `result`
FROM `currency_rates`
WHERE `currency` IN ('EUR','BGN')
ORDER BY `currency`;

-- C.2 — sanity-check the magnitudes. Every rate is now "EUR per 1 unit", so a
-- currency weaker than the euro must be < 1 and GBP must be > 1. A row that is
-- still ~1.95× its expected value means B.2 did not run.
SELECT
  'C.2 magnitudes' AS `check`,
  `currency`,
  `rate_to_eur`,
  CASE
    WHEN `currency` = 'GBP' AND `rate_to_eur` BETWEEN 0.8  AND 2.0  THEN 'OK'
    WHEN `currency` = 'GBP'                                          THEN 'FAIL — GBP out of range, still leva-based?'
    WHEN `rate_to_eur` >= 1.5                                        THEN 'WARN — suspiciously large for a EUR-based rate'
    ELSE 'OK'
  END AS `result`
FROM `currency_rates`
ORDER BY `rate_to_eur` DESC;

-- C.3 — nothing the BNB job owns is left flagged fixed, and nothing fixed is
-- left for it to fetch. Expect only EUR/BGN as fixed, all with source 'fixed'.
SELECT
  'C.3 fixed vs fetchable' AS `check`,
  `is_fixed`,
  `source`,
  COUNT(*)                 AS `rows`,
  GROUP_CONCAT(`currency` ORDER BY `currency` SEPARATOR ', ') AS `currencies`,
  CASE
    WHEN `is_fixed` = 1 AND `source` <> 'fixed' THEN 'FAIL — fixed row not marked source=fixed'
    WHEN `is_fixed` = 0 AND `source` =  'fixed' THEN 'FAIL — source=fixed but the job may overwrite it'
    ELSE 'OK'
  END AS `result`
FROM `currency_rates`
GROUP BY `is_fixed`, `source`
ORDER BY `is_fixed` DESC, `source`;
