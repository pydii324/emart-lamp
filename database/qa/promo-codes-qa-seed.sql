-- =============================================================================
-- QA фикстури за ръчното тестване на промо кодовете (issue #610)
-- Цел: imartap САМО. `promo_codes` е споделеният каталог (виж fresh/06).
-- Пускане: mysql -D imartap < promo-codes-qa-seed.sql
--
-- ТОВА НЕ Е МИГРАЦИЯ. Останалите файлове под database/migrations/ са нарочно
-- fail-fast и не се пускат втори път. Този тук е обратното — пуска се колкото
-- пъти искаш. Тестването изгаря кодове (`times_used` расте, количките се
-- пълнят), така че фикстурите трябва да се връщат в начално състояние с една
-- команда. Затова започва с DELETE на собствените си редове.
--
-- Всички кодове са `site='bg'` (валута EUR — PromoRegion::CURRENCY['bg']),
-- освен QARO, който нарочно е на друг регион. Един регион = една валута, нищо
-- не се конвертира — сумите тук са точно това, което се вади от количката.
--
-- НЕ пускай това на продукция. Маркерът е `created_by='qa-seed'`.
-- =============================================================================

SET NAMES utf8mb4;

-- --- 0. Изчистване -----------------------------------------------------------
-- Собствените редове: за да е re-runnable.
DELETE FROM `promo_codes` WHERE `created_by` = 'qa-seed';

-- Два реда от `fresh-seed`, които пречат на тестването (стари инстанции):
--   SHIPPCT50     — type 'shipping_percent'. Типът е премахнат изцяло (20.09.2026):
--                   няма го нито в DB ENUM-а, нито в PHP. Код от този тип не бива
--                   да се тества.
--   VOUCHER500ALL — само старият вариант със site='bg' и currency='ALL'. Остатък от
--                   конверсионния слой, махнат на 10.09; нарушава инварианта
--                   „един регион = една валута" и дава подвеждащи суми. От 21.09
--                   fresh/08 го seed-ва като site='al', където е коректен — затова
--                   DELETE-ът го хваща по site, а не по код.
DELETE FROM `promo_codes`
 WHERE `created_by` = 'fresh-seed'
   AND (`code` = 'SHIPPCT50' OR (`code` = 'VOUCHER500ALL' AND `site` = 'bg'));

-- --- 1. Фикстури за валидацията (чеклист 1.1) --------------------------------
-- Всеки от тези трябва да бъде ОТХВЪРЛЕН с конкретно съобщение. Редът в
-- PromoCodeCatalog::rejectionReason() е match(true) отгоре надолу и е контракт:
-- active → expired → min_subtotal → вече приложен. QAINACTIVE нарочно е и
-- изтекъл, за да се види, че „не е активен" бие „изтекъл".
INSERT INTO `promo_codes`
  (`code`, `type`, `subtype`, `discount_value`, `min_subtotal`, `shipping_cap`, `max_uses`, `times_used`, `active`, `stack_group`, `expiration_date`, `created_at`, `source`, `note`, `site`, `created_by`) VALUES
  ('QAINACTIVE', 'percent', NULL, 10.00, 0.00, NULL, 0, 0, 0, NULL, '20240101000000', DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'QA: active=0 И изтекъл -> "Кодът не е активен" (active бие expired)', 'bg', 'qa-seed'),
  ('QAEXPIRED',  'percent', NULL, 10.00, 0.00, NULL, 0, 0, 1, NULL, '20240101000000', DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'QA: изтекъл -> "Кодът е изтекъл"', 'bg', 'qa-seed'),
  ('QAMIN50',    'percent', NULL, 10.00,50.00, NULL, 0, 0, 1, NULL, NULL,             DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'QA: min_subtotal -> "Минимална сума за код: 50.00 <валута>"', 'bg', 'qa-seed'),
  ('QAUSEDUP',   'percent', NULL, 10.00, 0.00, NULL, 1, 1, 1, NULL, NULL,             DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'QA: вече изчерпан -> "Кодът е изчерпан"', 'bg', 'qa-seed'),
  ('QARO',       'percent', NULL, 10.00, 0.00, NULL, 0, 0, 1, NULL, NULL,             DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'QA: чужд регион -> "Невалиден код" (умишлено неразличимо от несъществуващ)', 'ro', 'qa-seed');

-- --- 2. Stack group (чеклист 1.1 #9) -----------------------------------------
-- Двата са в група 1: вторият трябва да върне
-- "Не може да се комбинира с вече приложен код от същата група".
-- Проверката е ПРЕДИ max_uses — нарочно, за да не се хаби код, който не може
-- да се приложи (PromoCodeCatalog.php:57-67).
INSERT INTO `promo_codes`
  (`code`, `type`, `subtype`, `discount_value`, `min_subtotal`, `shipping_cap`, `max_uses`, `times_used`, `active`, `stack_group`, `expiration_date`, `created_at`, `source`, `note`, `site`, `created_by`) VALUES
  ('QASTACKA', 'percent', NULL, 10.00,0.00, NULL, 0, 0, 1, 1, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'QA: stack_group 1, първи', 'bg', 'qa-seed'),
  ('QASTACKB', 'percent', NULL, 15.00,0.00, NULL, 0, 0, 1, 1, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'QA: stack_group 1, втори -> конфликт', 'bg', 'qa-seed');

-- --- 3. Percent (чеклист 1.2 #13, #14) ---------------------------------------
-- Двата заедно: прилага се САМО QAPCT20. QAPCT10 остава в количката с
-- discount_applied = 0 и НЕ се инвалидира (PromoCalc.php:62-69).
-- Нито един от двата не прави отделен ред — рендерът е задраскана цена до
-- артикула (PriceDisplay::oldUnit()).
INSERT INTO `promo_codes`
  (`code`, `type`, `subtype`, `discount_value`, `min_subtotal`, `shipping_cap`, `max_uses`, `times_used`, `active`, `stack_group`, `expiration_date`, `created_at`, `source`, `note`, `site`, `created_by`) VALUES
  ('QAPCT10', 'percent', NULL, 10.00,0.00, NULL, 0, 0, 1, NULL, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'QA: 10% — по-малкият от двойката', 'bg', 'qa-seed'),
  ('QAPCT20', 'percent', NULL, 20.00,0.00, NULL, 0, 0, 1, NULL, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'QA: 20% — печели при двойка percent кодове', 'bg', 'qa-seed');

-- --- 4. Fixed: ваучер и купон (чеклист 1.2 #15-#18) --------------------------
-- Тези ДА правят отделен отрицателен ред в количката:
--   subtype voucher -> SKU 5555555,  subtype coupon -> SKU 7777777
-- QAVOUCHERBIG е нарочно по-голям от всяка тестова количка: трябва да се капне
-- на количката, да изгори цял (без остатък) и остатъкът да прелее върху
-- доставката, но не под 0.
INSERT INTO `promo_codes`
  (`code`, `type`, `subtype`, `discount_value`, `min_subtotal`, `shipping_cap`, `max_uses`, `times_used`, `active`, `stack_group`, `expiration_date`, `created_at`, `source`, `note`, `site`, `created_by`) VALUES
  ('QAVOUCHER5',   'fixed', 'voucher',   5.00,0.00, NULL, 0, 0, 1, NULL, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'QA: ваучер 5.00 -> отрицателен ред SKU 5555555', 'bg', 'qa-seed'),
  ('QACOUPON5',    'fixed', 'coupon',    5.00,0.00, NULL, 0, 0, 1, NULL, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'QA: купон 5.00 -> отрицателен ред SKU 7777777', 'bg', 'qa-seed'),
  ('QAVOUCHERBIG', 'fixed', 'voucher', 500.00,0.00, NULL, 0, 0, 1, NULL, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'QA: ваучер 500.00 -> капва се на количката, изгаря цял, прелива върху доставката', 'bg', 'qa-seed');

-- --- 5. Shipping (чеклист 1.2 #19-#21) ---------------------------------------
-- `discount_value` не се чете за shipping — таванът е `shipping_cap`:
--   NULL = без таван, цялата доставка пада
--   3.00 = сваля най-много 3.00
--   0.00 = НЕ сваля нищо. NULL и 0.00 НЕ са едно и също — точно затова
--          api/promo-cart.php:134-147 пише NULL като SQL литерал вместо да го
--          bind-ва (dbq() маппва null към "", а "" в DECIMAL става 0.00).
-- ВАЖНО: количката трябва да е ПОД прага за безплатна доставка, иначе няма
-- какво да се сваля. Виж README.md, секция „Прагове на доставката".
INSERT INTO `promo_codes`
  (`code`, `type`, `subtype`, `discount_value`, `min_subtotal`, `shipping_cap`, `max_uses`, `times_used`, `active`, `stack_group`, `expiration_date`, `created_at`, `source`, `note`, `site`, `created_by`) VALUES
  ('QAFREESHIP',  'shipping', NULL, 0.00,0.00, NULL, 0, 0, 1, NULL, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'QA: без таван -> цялата доставка пада', 'bg', 'qa-seed'),
  ('QASHIPCAP3',  'shipping', NULL, 0.00,0.00, 3.00, 0, 0, 1, NULL, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'QA: таван 3.00 -> сваля най-много 3.00', 'bg', 'qa-seed'),
  ('QASHIPCAP0',  'shipping', NULL, 0.00,0.00, 0.00, 0, 0, 1, NULL, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'QA: таван 0.00 -> не сваля НИЩО (различно от NULL)', 'bg', 'qa-seed');

-- --- 6. Еднократен код за финализиране и race теста (чеклист 1.6 #41) --------
-- max_uses=1, times_used=0. След завършена поръчка times_used трябва да е 1 и
-- вторият опит да върне "Кодът е изчерпан". Гардът е в WHERE-а на UPDATE-а, не
-- в PHP (PromoCodeCatalog.php:136-140) — две паралелни заявки, само едната
-- вдига брояча.
INSERT INTO `promo_codes`
  (`code`, `type`, `subtype`, `discount_value`, `min_subtotal`, `shipping_cap`, `max_uses`, `times_used`, `active`, `stack_group`, `expiration_date`, `created_at`, `source`, `note`, `site`, `created_by`) VALUES
  ('QAONESHOT', 'fixed', 'voucher', 5.00,0.00, NULL, 1, 0, 1, NULL, NULL, DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 'manual', 'QA: max_uses=1 -> за финализиране и race теста', 'bg', 'qa-seed');

-- --- Проверка ----------------------------------------------------------------
SELECT `id`, `code`, `type`, `subtype`, `discount_value`, `min_subtotal`,
       `shipping_cap`, `max_uses`, `times_used`, `active`, `stack_group`, `expiration_date`, `site`
FROM `promo_codes` WHERE `created_by` = 'qa-seed' ORDER BY `id`;
