-- =============================================================================
-- DEPLOY 09 — promo_codes: UNIQUE(code) → UNIQUE(code, site), plain SQL
-- =============================================================================
-- Run MANUALLY. imartap ONLY — promo_codes is the shared catalog.
--
-- WHY:
--   `code` alone is UNIQUE today, so the SAME code string can never exist twice
--   even across different regions. deploy/08 hit this directly: bringing back
--   the staff wildcard as per-region rows needs `slujeben10bg` / `slujeben10ro`
--   / ... instead of one `slujeben10` shared by all. The real invariant is
--   "one code per region", not "one code globally" — the constraint should be
--   (code, site).
--
-- CAVEAT — `site` is live VARCHAR(10) NULL, not an ENUM (no enforcement, see
--   deploy/07). Two rows with the same `code` and `site` = NULL do NOT collide
--   under a UNIQUE index (MySQL treats NULLs as distinct), so this alone does
--   not dedupe legacy rows with a blank/NULL site. That backfill is a separate,
--   already-tracked gate — do not treat this migration as covering it.
--
-- Not idempotent: DROP INDEX errors (1091) if `code` is already gone, ADD
-- errors (1061/1062) if `uq_code_site` already exists or a live duplicate
-- (code, site) pair exists. Either error is the signal — check first with:
--   SELECT `code`, `site`, COUNT(*) FROM `promo_codes`
--   GROUP BY `code`, `site` HAVING COUNT(*) > 1;
-- =============================================================================

ALTER TABLE `promo_codes`
  DROP INDEX `code`,
  ADD UNIQUE KEY `uq_code_site` (`code`, `site`);
