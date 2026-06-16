-- =============================================================================
-- Catalog promo SKUs — продукти за Микроинвест negative редове
-- =============================================================================
-- issue #610 (drago 27.05): промо отстъпките стигат до Микроинвест като редове
-- в `item` с предефинирани cat_no-та. Продуктите трябва да съществуват в
-- `catalog` с cena = 0 (security).
--
--   5555555 | Ваучер ЕМ АРТ              (type=fixed; текущо emit-ва PromoCode)
--   6666666 | Безплатна доставка         (резерв — shipping е през cendost)
--   7777777 | Купон за отстъпка          (резерв — fixed може да мине през тук)
--   8888888 | Процентна отстъпка         (резерв — percent е в цените, без ред)
--
-- Текущо storefront-ът emit-ва само 5555555 (виж lib/db-switch.php
-- PROMO_FIXED_CAT_NO). Останалите се seed-ват за future-proof.
--
-- `catalog` живее само в регионалните бази (НЕ в imartap). Guard по table
-- existence → no-op срещу imartap. Idempotent (INSERT IGNORE по UNIQUE cat_no).
-- Без stored procedures (batch splitter split-ва на ';').
-- =============================================================================

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'catalog'),
  'INSERT IGNORE INTO `catalog` (`cat_no`, `ime`, `miarka`, `cena`, `nnindex`) VALUES
     (''5555555'', ''Промо ваучер/купон'', ''бр.'', 0.00, ''promo-5555555''),
     (''6666666'', ''Промо безплатна доставка'', ''бр.'', 0.00, ''promo-6666666''),
     (''7777777'', ''Промо купон'', ''бр.'', 0.00, ''promo-7777777''),
     (''8888888'', ''Промо процентна отстъпка'', ''бр.'', 0.00, ''promo-8888888'')',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
