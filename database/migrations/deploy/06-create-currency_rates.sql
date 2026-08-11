-- =============================================================================
-- DEPLOY 06 — currency_rates (FX rate table)
-- =============================================================================
-- Run against imartap ONLY (shared catalog / source of truth). Unlike the ALTER
-- deploys in this folder, this one IS idempotent (CREATE IF NOT EXISTS + seed
-- guarded by NOT EXISTS) — safe to re-run; it will NOT clobber a live floating
-- rate the updater job has already written.
--
--   mysql -D imartap < deploy/06-create-currency_rates.sql
--
-- Base currency = BGN. rate_to_bgn = how many BGN one unit of `currency` buys.
-- is_fixed=1 rows (BGN, EUR) are legally fixed and MUST be skipped by the
-- rate-updater (scripts/update-currency-rates.php) — only floating rows are fetched.
--
-- Consumed by lib/PromoCode.php (PromoCode::toBgn / ratesToBgn) to normalise
-- promo money-fields from the code's currency → BGN at the catalog read boundary.
-- =============================================================================

CREATE TABLE IF NOT EXISTS `currency_rates` (
  `currency`    CHAR(3)        NOT NULL                COMMENT 'ISO 4217: BGN (base), EUR, RON, ...',
  `rate_to_bgn` DECIMAL(18,8)  NOT NULL                COMMENT '1 unit of `currency` = rate_to_bgn BGN',
  `is_fixed`    TINYINT(1)     NOT NULL DEFAULT 0      COMMENT '1 = legally fixed (irrevocable); updater MUST skip',
  `source`      VARCHAR(16)    NOT NULL DEFAULT 'manual' COMMENT 'fixed | bnb | manual',
  `updated_at`  DATETIME       NULL     DEFAULT NULL   COMMENT 'last refresh; NULL until first job run',
  PRIMARY KEY (`currency`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- BGN — base currency (self). Fixed.
INSERT INTO `currency_rates` (`currency`, `rate_to_bgn`, `is_fixed`, `source`, `updated_at`)
SELECT 'BGN', 1.00000000, 1, 'fixed', NULL
WHERE NOT EXISTS (SELECT 1 FROM `currency_rates` WHERE `currency` = 'BGN');

-- EUR — irrevocable BGN adoption rate 1 EUR = 1.95583 BGN. Fixed, never fetched.
INSERT INTO `currency_rates` (`currency`, `rate_to_bgn`, `is_fixed`, `source`, `updated_at`)
SELECT 'EUR', 1.95583000, 1, 'fixed', NULL
WHERE NOT EXISTS (SELECT 1 FROM `currency_rates` WHERE `currency` = 'EUR');

-- RON — floating (Romania). Placeholder ~ recent value; refreshed by the BNB job.
INSERT INTO `currency_rates` (`currency`, `rate_to_bgn`, `is_fixed`, `source`, `updated_at`)
SELECT 'RON', 0.39350000, 0, 'bnb', NULL
WHERE NOT EXISTS (SELECT 1 FROM `currency_rates` WHERE `currency` = 'RON');

-- ALL — Albanian lek. Floating, but BNB does NOT publish it → source 'manual';
-- the BNB job leaves it untouched. Placeholder ~ 1 lek; update by hand or point
-- the fetch at a provider that carries lek (e.g. Bank of Albania).
INSERT INTO `currency_rates` (`currency`, `rate_to_bgn`, `is_fixed`, `source`, `updated_at`)
SELECT 'ALL', 0.01960000, 0, 'manual', NULL
WHERE NOT EXISTS (SELECT 1 FROM `currency_rates` WHERE `currency` = 'ALL');
