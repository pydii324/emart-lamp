-- Phase 2 follow-up: track which employee used a promo code.
-- Adds:
--   used_by_employeeId INT NULL on order_promo_codes (admin/backoffice app populates it)
--
-- This column mirrors the legacy `obshti_kodove.potrebitel` field. The storefront
-- (public_html) has NO employee/operator session and does NOT write this column —
-- rows it inserts via PromoCode::markUsed() leave it NULL. A separate admin/backoffice
-- application (not in this repo) sets the employee id.
--
-- Idempotent + table-existence safe: the ALTER runs only when the table exists in
-- the connected DB AND the column is missing. Targets DATABASE() so it is safe to
-- run via sql-batch-dbs.ts. order_promo_codes lives only in `imartap`, so this is
-- a no-op against regional DBs. Re-running is a no-op. No stored procedures
-- (the batch splitter splits on ';').

-- order_promo_codes.used_by_employeeId
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'order_promo_codes')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'order_promo_codes' AND COLUMN_NAME = 'used_by_employeeId'),
  'ALTER TABLE `order_promo_codes` ADD COLUMN `used_by_employeeId` INT NULL DEFAULT NULL COMMENT ''Employee who used the code (admin/backoffice app; legacy obshti_kodove.potrebitel)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
