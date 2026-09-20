-- =============================================================================
-- 16 — promo_codes.type: махни 'shipping_percent'
-- Target: imartap ONLY (promo_codes е споделеният каталог).
-- Run: mysql -D imartap --default-character-set=utf8mb4 < 16-drop-shipping_percent-type.sql
--
-- ⚠ НЕ Е БЕЗОПАСНО ПРИ ОСТАНАЛИ РЕДОВЕ — И ТОВА Е СИГНАЛЪТ
--   MySQL реже стойност извън новия ENUM до '' (в strict режим — ERROR 1265
--   "Data truncated for column 'type'"), така че ALTER-ът гърми, ако е останал
--   жив код от този тип. Провери и изчисти на ръка ПРЕДИ да пуснеш файла:
--
--     SELECT id, code, site, active, times_used FROM promo_codes
--      WHERE type = 'shipping_percent';
--
--   Такъв код няма какво да отстъпи и след PHP промяната: shipDiscountForRow()
--   го чете като непознат тип и връща 0.00.
--
-- WHY
--   'shipping_percent' (процент от цената на доставката, капнат от shipping_cap)
--   отпадна от бизнес логиката — плоският 'shipping' покрива случая. Стойността
--   беше махната от fresh/01 и fresh/06 на 2026-08-21, но живите бази още я
--   приемат, а PHP я имплементираше докрай. На 20.09.2026 тя пада и от PHP
--   (lib/PromoCalc.php, lib/PromoCodeCatalog.php, promo-input.php,
--   promo-cart-rows.php, the-marketer/promo-codes.php — ?type=3 вече връща 400),
--   така че DB-то не бива да може да я записва повече.
--
--   Дефиницията по-долу е байт-идентична с fresh/06 — след този ALTER живата
--   схема и fresh схемата съвпадат.
--
-- Регионалните бази (cart_promo_codes) се пипат от 17.
--
-- SET NAMES utf8mb4 не е излишно: MODIFY предеклалира колоната, а не бива да
-- влачи latin1 клиентска връзка върху таблица с кирилски COMMENT-и.
-- =============================================================================

SET NAMES utf8mb4;

ALTER TABLE `promo_codes`
  MODIFY `type` ENUM('percent','fixed','shipping') NOT NULL DEFAULT 'percent';
