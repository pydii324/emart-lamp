-- =============================================================================
-- Voucher burn: drop promo_codes.voucher_remainer
-- =============================================================================
-- Решение от issue #610 (drago 08.06): ваучерът се изразходва изцяло при
-- употреба — няма "remainder budget" пренасян между поръчки. Колоната
-- voucher_remainer вече не се ползва от PHP-то (PromoCode/PromoCalc) и се
-- премахва.
--
-- За FRESH install (new/01 вече не създава колоната) — този скрипт е no-op.
-- За бази, мигрирани преди voucher burn (staging emart.al/almarta, dev) —
-- drop-ва колоната. Idempotent + table/column-existence guarded; таргетира
-- DATABASE() (промо таблиците са само в imartap). Без stored procedures.
-- =============================================================================

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'promo_codes' AND COLUMN_NAME = 'voucher_remainer'),
  'ALTER TABLE `promo_codes` DROP COLUMN `voucher_remainer`',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
