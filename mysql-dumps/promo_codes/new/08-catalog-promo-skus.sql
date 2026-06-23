-- =============================================================================
-- 08 — Seed catalog SKUs for Microinvest negative rows
-- Target: regional DBs (catalog table lives in regional, not imartap)
-- Idempotent: INSERT IGNORE + table-existence guard
-- SKUs: 5555555 voucher, 6666666 free shipping (reserve),
--       7777777 coupon, 8888888 percent (reserve)
-- =============================================================================

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'catalog'),
  'INSERT IGNORE INTO `catalog` (`cat_no`, `ime`, `miarka`, `cena`, `nnindex`) VALUES
     (''5555555'', ''Промо ваучер/купон'',       ''бр.'', 0.00, ''promo-5555555''),
     (''6666666'', ''Промо безплатна доставка'', ''бр.'', 0.00, ''promo-6666666''),
     (''7777777'', ''Промо купон'',              ''бр.'', 0.00, ''promo-7777777''),
     (''8888888'', ''Промо процентна отстъпка'', ''бр.'', 0.00, ''promo-8888888'')',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
