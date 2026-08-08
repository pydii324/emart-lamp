-- =============================================================================
-- 03 — promo_codes: park non-region `site` values on NULL
-- Target: imartap ONLY (promo_codes is the shared catalog and lives there alone).
-- Run: mysql -D imartap < 03-park-unconvertible-sites.sql
--
-- ⚠ MUST run BEFORE 04, while the column is still wide enough to hold the old
--   values. This is what makes 04's ENUM conversion lossless.
--
-- Plain SQL, no guards. Three UPDATEs — naturally a no-op on a second run (0
-- rows matched), so unlike the rest of the set this file does not fail loudly if
-- repeated. It writes nothing on an instance whose `site` is already
-- ENUM('bg','ro','gr','al') NOT NULL: that ENUM never let a bad value in. Only
-- VARCHAR instances (and the retired 'all' wildcard rows) have work here.
--
-- 00-preflight check G lists exactly which rows this touches. Read it first — an
-- ACTIVE row in that list is a code someone believes works and does not.
--
-- WHY: file 04 narrows `site` to an ENUM of the 37 real regions. Converting a
-- value the ENUM lacks truncates it to '' (or errors under STRICT mode), so the
-- unconvertible ones are moved to NULL first — which is why 04 declares the
-- column NULLable while fresh/06 (virgin DB, no legacy rows) declares it NOT NULL.
-- Both shapes are correct for their target.
--
-- NULL is the honest value, not a loss: siteSql() emits `site IN ('bg')`-style
-- SQL and `IN` never matches NULL, and siteAllows() compares with === against a
-- string — so a NULL-site row is unredeemable in every region, which is exactly
-- what these rows already were. The retired 'all' wildcard used to mean "valid
-- everywhere"; lib/PromoCode.php matches the region exactly now, so an 'all' row
-- has been dead since that change. The old value is preserved in `note`.
-- =============================================================================


-- ── 1. Preserve the old value in `note` ──────────────────────────────────────
-- LEFT(...,255) keeps the result inside note's VARCHAR(255) instead of erroring
-- under STRICT mode. The marker is PREPENDED, not appended: on a note already
-- near 255 chars an appended marker would be the part that LEFT() chops off, and
-- the row would lose the only record of what its region used to be.
UPDATE `promo_codes`
   SET `note` = LEFT(CONCAT('[retired site=', `site`, '] ', COALESCE(`note`, '')), 255)
 WHERE `site` IS NOT NULL
   AND `site` NOT IN ('bg','ro','gr','al',
                      'en','md','at','cz','de','es','hr','hu','it','pl','si','sk','cy','uk','us','co',
                      'be','dk','ee','fi','fr','lt','lv','nl','pt','se','mk','rs','ua','tr','ru',
                      'biz','org');


-- ── 2. Deactivate them ───────────────────────────────────────────────────────
-- Once `site` is NULL nothing in the PHP would ever surface these codes, so an
-- active flag on an unreachable one is just noise that trips file 07 check D.
--
-- `site IS NULL` is spelled out separately because `NULL NOT IN (…)` evaluates
-- to NULL, not TRUE — without it a pre-existing NULL-site row would stay flagged
-- active.
UPDATE `promo_codes`
   SET `active` = 0
 WHERE `active` = 1
   AND (`site` IS NULL
    OR  `site` NOT IN ('bg','ro','gr','al',
                       'en','md','at','cz','de','es','hr','hu','it','pl','si','sk','cy','uk','us','co',
                       'be','dk','ee','fi','fr','lt','lv','nl','pt','se','mk','rs','ua','tr','ru',
                       'biz','org'));


-- ── 3. Park the value itself ─────────────────────────────────────────────────
-- A separate statement from 1 and 2 on purpose: those two must read the old
-- value, this one destroys it.
UPDATE `promo_codes`
   SET `site` = NULL
 WHERE `site` NOT IN ('bg','ro','gr','al',
                      'en','md','at','cz','de','es','hr','hu','it','pl','si','sk','cy','uk','us','co',
                      'be','dk','ee','fi','fr','lt','lv','nl','pt','se','mk','rs','ua','tr','ru',
                      'biz','org');
