-- =============================================================================
-- DEPLOY 08 — Retire the `site = 'all'` wildcard, plain SQL
-- =============================================================================
-- Run MANUALLY. Plain statements — no guards. Idempotent: a second run updates
-- 0 rows.
--
-- WHERE TO RUN:
--   • imartap ONLY — `promo_codes` is the shared catalog and lives there alone
--     (the regional DBs carry only the cart/order pivots).
--
-- WHY:
--   `site = 'all'` used to mean "valid on every region". lib/PromoCode.php no
--   longer honours it — siteSql() / siteAllows() now match the current region
--   exactly, so an 'all' row is unredeemable everywhere. Reasons for dropping
--   the wildcard:
--     • `site` is VARCHAR(10) NULL on the live imartap, so nothing enforces the
--       value; 'al' (Albania, a real region) and 'all' differ by one letter, and
--       a typo silently turned one region's code into a storefront-wide one.
--     • A wildcard code has no single currency — PromoCode::SITE_CURRENCY has no
--       entry for it, and every live 'all' row is currency 'BGN', so a `fixed`
--       one was deducted at its BGN face value on ro / gr / al too.
--     • the-marketer's generator can never emit 'all' (it whitelists the region
--       against SITE_CURRENCY), so the wildcard was hand-authored only.
--
-- WHAT THIS DOES:
--   Deactivates the leftover wildcard rows (10 on dev imartap: the staff codes
--   `slujeben5/10/15/20/slujebentest` plus `GFCF9HAD` and 4 already-inactive
--   ones). `site` is deliberately LEFT AS 'all' — it is the audit trail of what
--   these rows were, and the PHP ignores the value either way.
--
--   Deploy the PHP and this file together. Either order is safe: the PHP alone
--   already makes the codes unredeemable, and this file alone only deactivates
--   codes that were about to stop working.
--
-- SIDE EFFECT:
--   A cart that already has a staff code applied loses it on the next render —
--   PromoCode::revalidate() drops it with reason `wrong_site` and citte/case.php
--   shows the "не важи за този сайт" banner. Self-healing, nothing to run.
--
--   Staff lose the cross-region discount. Bringing it back means one row per
--   region again. Before deploy/09 (UNIQUE(code) → UNIQUE(code, site)) that
--   meant a DIFFERENT code string per region (e.g. `slujeben10bg`,
--   `slujeben10ro`); after deploy/09 the same code string is fine as long as
--   each row has a distinct `site`.
-- =============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- Section A — deactivate the wildcard rows   (imartap ONLY)
-- ═══════════════════════════════════════════════════════════════════════════
UPDATE `promo_codes`
   SET `active` = 0
 WHERE `site` = 'all'
   AND `active` = 1;


-- ═══════════════════════════════════════════════════════════════════════════
-- Section B — verification (read-only, writes NOTHING)
-- ═══════════════════════════════════════════════════════════════════════════
-- Expect: every remaining 'all' row is active = 0. Any row with active = 1 here
-- means Section A did not run.
SELECT
  'A. wildcard rows deactivated' AS `check`,
  `active`,
  COUNT(*)                       AS `rows`,
  IF(`active` = 0, 'OK', 'FAIL — still redeemable-flagged') AS `result`
FROM `promo_codes`
WHERE `site` = 'all'
GROUP BY `active`
ORDER BY `active`;

-- Expect: only regions from PromoCode::SITES (plus the retired 'all'). Anything
-- else is a typo'd region — those rows are unredeemable and want a manual fix.
-- The list below is the 37-region one; on an instance that has not yet run
-- deploy/10 only the first four can actually occur.
SELECT
  'B. site values in use' AS `check`,
  `site`,
  COUNT(*)                AS `rows`,
  CASE
    WHEN `site` = 'all'  THEN 'retired wildcard — inactive, kept for audit'
    -- NULL is not a typo here: deploy/10 parks the wildcard and any unknown
    -- region on NULL when it converts `site` to the 37-region ENUM, and stamps
    -- the old value into `note`. Those rows are inactive and unredeemable by
    -- design, so this arm must come before the whitelist below (a CASE arm that
    -- tests `site IN (…)` can never match NULL anyway — it evaluates to NULL).
    WHEN `site` IS NULL  THEN 'parked by deploy/10 — inactive, old value is in `note`'
    WHEN `site` IN ('bg','ro','gr','al',
                    'en','md','at','cz','de','es','hr','hu','it','pl','si','sk','cy','uk','us','co',
                    'be','dk','ee','fi','fr','lt','lv','nl','pt','se','mk','rs','ua','tr','ru',
                    'biz','org') THEN 'OK'
    ELSE 'WARN — unknown region, these codes can never be redeemed'
  END AS `result`
FROM `promo_codes`
GROUP BY `site`
ORDER BY `rows` DESC;
