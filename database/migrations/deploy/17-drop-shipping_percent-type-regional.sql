-- =============================================================================
-- 17 — cart_promo_codes.type: махни 'shipping_percent'
-- Target: ВСЯКА регионална база (cart_promo_codes е регионална — виж fresh/01).
-- Run: mysql -D <regional_db> --default-character-set=utf8mb4 < 17-drop-shipping_percent-type-regional.sql
--      (по веднъж за всеки регион)
--
-- ⚠ Същото като 16: ALTER-ът гърми с ERROR 1265, ако в някоя жива количка е
--   останал приложен код от този тип. Провери и изчисти ПРЕДИ пускане:
--
--     SELECT id, cart_id, cart_type, code FROM cart_promo_codes
--      WHERE type = 'shipping_percent';
--
--   Редът е snapshot на каталожния код — изтриването му просто маха чипа от
--   количката, поръчките не го носят (order_promo_codes няма `type`).
--
-- WHY: виж 16-drop-shipping_percent-type.sql. Дефиницията е байт-идентична с
-- fresh/01 — двете таблици трябва да имат един и същ списък типове.
-- =============================================================================

SET NAMES utf8mb4;

ALTER TABLE `cart_promo_codes`
  MODIFY `type` ENUM('percent','fixed','shipping') NOT NULL;
