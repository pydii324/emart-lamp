-- =============================================================================
-- 19 — promo_codes.currency: махаме колоната
-- Target: САМО imartap (promo_codes живее само там).
-- Run: mysql -D imartap --table --default-character-set=utf8mb4 \
--        < 19-drop-promo_codes-currency.sql | tee 19-imartap-audit.txt
--
-- WHY: след deploy/15 промо логиката не конвертира нищо. discount_value,
-- min_subtotal и shipping_cap се ползват както са, във валутата на количката на
-- региона (`site`). Колоната само повтаряше PromoRegion::CURRENCY[site] и можеше
-- да му противоречи. Пример: код site='al', currency='EUR', discount_value=5
-- на emart.al сваля 5 лека, не 5 евро. Етикетът само подвеждаше и се
-- снапшотваше грешно в cart_promo_codes / order_promo_codes.
-- Сега PromoCodeCatalog::validate() взима валутата от региона.
-- Снапшот колоните `currency` в cart_promo_codes и order_promo_codes остават.
--
-- ⚠ Колоната се губи безвъзвратно. Затова A се пуска първа и изходът се пази
-- (tee-то горе). Редовете в A са кодове, писани с мисълта за друга валута. Там
-- discount_value / min_subtotal / shipping_cap трябва да се пре-оценят ръчно.
-- Това е бизнес решение, не част от миграцията.
-- =============================================================================

SET NAMES utf8mb4;

-- ── A. кодове, чиято currency не е валутата на региона им ──────────────────
-- CASE-ът е PromoRegion::CURRENCY; всичко извън списъка е EUR.
SELECT 'A. currency != region currency' AS `check`,
       `id`, `code`, `site`, `currency`,
       CASE `site`
         WHEN 'ro' THEN 'RON' WHEN 'al' THEN 'ALL' WHEN 'md' THEN 'MDL'
         WHEN 'cz' THEN 'CZK' WHEN 'hu' THEN 'HUF' WHEN 'pl' THEN 'PLN'
         WHEN 'uk' THEN 'GBP' WHEN 'us' THEN 'USD' WHEN 'co' THEN 'CAD'
         WHEN 'dk' THEN 'DKK' WHEN 'se' THEN 'SEK' WHEN 'mk' THEN 'MKD'
         WHEN 'rs' THEN 'RSD' WHEN 'ua' THEN 'UAH' WHEN 'tr' THEN 'TRY'
         WHEN 'ru' THEN 'RUB'
         ELSE 'EUR'
       END AS `region_currency`,
       `type`, `discount_value`, `min_subtotal`, `shipping_cap`, `active`, `expiration_date`
FROM `promo_codes`
HAVING `currency` <> `region_currency`
ORDER BY `site`, `id`;

-- ── B. drop ─────────────────────────────────────────────────────────────────
ALTER TABLE `promo_codes` DROP COLUMN `currency`;
