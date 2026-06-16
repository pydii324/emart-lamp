-- =============================================================================
-- Add `shipping_percent` promo type (issue #610, Q3: percent-off-delivery)
-- =============================================================================
-- Extends the `type` ENUM on `promo_codes` (imartap catalog) and on
-- `cart_promo_codes` (now regional; the imartap backup copy is also covered).
-- `order_promo_codes` has no `type` column → not touched.
--
-- Semantics: discount_value = percent of the delivery cost; shipping_cap =
-- optional flat cap on the resulting discount (NULL = uncapped). See PromoCalc::
-- shipDiscountForRow().
--
-- Idempotent + table-existence guarded against DATABASE(): re-running, or
-- running against a DB that lacks a given table, is a no-op. Run against imartap
-- (promo_codes + cart_promo_codes backup) AND each regional DB (cart_promo_codes).
-- =============================================================================

-- promo_codes.type (catalog) — keeps DEFAULT 'percent'
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'promo_codes')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'promo_codes'
             AND COLUMN_NAME = 'type' AND COLUMN_TYPE LIKE '%shipping_percent%'),
  'ALTER TABLE `promo_codes` MODIFY COLUMN `type` ENUM(''percent'',''fixed'',''shipping'',''shipping_percent'') NOT NULL DEFAULT ''percent''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

-- cart_promo_codes.type (pivot) — no DEFAULT, matches the create scripts
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cart_promo_codes')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cart_promo_codes'
             AND COLUMN_NAME = 'type' AND COLUMN_TYPE LIKE '%shipping_percent%'),
  'ALTER TABLE `cart_promo_codes` MODIFY COLUMN `type` ENUM(''percent'',''fixed'',''shipping'',''shipping_percent'') NOT NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
