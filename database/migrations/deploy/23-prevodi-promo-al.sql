-- =============================================================================
-- 23 — promenliviprevodi: промо кодовете на албански (3101–3108, 3250–3265)
-- Target: САМО al регионалната база.
-- Run: mysql -D <al_db> --default-character-set=utf8mb4 < 23-prevodi-promo-al.sql
-- Prereq: 20-seed-promo-prevodi.sql и 21-seed-promo-prevodi-errors.sql на същата база.
--
-- WHY: seed 20 и 21 слагат български текст навсякъде, така че al сайтът
-- показваше „Невалиден код" (QA #48). Тук идва текстът на албански.
--
-- `AND du = '<български>'`: пипа само ред, който още е seed-натият български.
-- Ред, вече редактиран от преводач, остава. Повторно пускане е no-op.
-- {code} и {amount} се попълват със strtr() — запазете ги.
--
-- Проверка след пускане (очаквано: 0 реда):
--     SELECT id, du FROM promenliviprevodi
--     WHERE (id BETWEEN 3101 AND 3108 OR id BETWEEN 3250 AND 3265)
--       AND du REGEXP '[А-Яа-я]';
-- =============================================================================

SET NAMES utf8mb4;

UPDATE `promenliviprevodi` SET `du` = 'Vendosni kodin promocional' WHERE `id` = 3101 AND `du` = 'Въведи промо код';
UPDATE `promenliviprevodi` SET `du` = 'Apliko' WHERE `id` = 3102 AND `du` = 'Приложи';
UPDATE `promenliviprevodi` SET `du` = 'Transport falas' WHERE `id` = 3103 AND `du` = 'Безплатна доставка';
UPDATE `promenliviprevodi` SET `du` = 'deri në' WHERE `id` = 3104 AND `du` = 'до';
UPDATE `promenliviprevodi` SET `du` = 'Gabim në lidhje' WHERE `id` = 3105 AND `du` = 'Грешка при свързване';
UPDATE `promenliviprevodi` SET `du` = 'Kod promocional' WHERE `id` = 3106 AND `du` = 'Промо код';
UPDATE `promenliviprevodi` SET `du` = '(transporti)' WHERE `id` = 3107 AND `du` = '(доставка)';
UPDATE `promenliviprevodi` SET `du` = 'Zbritje për transportin' WHERE `id` = 3108 AND `du` = 'Отстъпка за доставка';
UPDATE `promenliviprevodi` SET `du` = 'Kod i pavlefshëm' WHERE `id` = 3250 AND `du` = 'Невалиден код';
UPDATE `promenliviprevodi` SET `du` = 'Shporta është bosh' WHERE `id` = 3251 AND `du` = 'Количката е празна';
UPDATE `promenliviprevodi` SET `du` = 'Gabim i përkohshëm, provoni përsëri' WHERE `id` = 3252 AND `du` = 'Временна грешка, опитай пак';
UPDATE `promenliviprevodi` SET `du` = 'Nuk mund të kombinohet me një kod tashmë të aplikuar nga i njëjti grup' WHERE `id` = 3253 AND `du` = 'Не може да се комбинира с вече приложен код от същата група';
UPDATE `promenliviprevodi` SET `du` = 'Kodi është shteruar' WHERE `id` = 3254 AND `du` = 'Кодът е изчерпан';
UPDATE `promenliviprevodi` SET `du` = 'Kodi nuk është aktiv' WHERE `id` = 3255 AND `du` = 'Кодът не е активен';
UPDATE `promenliviprevodi` SET `du` = 'Kodi ka skaduar' WHERE `id` = 3256 AND `du` = 'Кодът е изтекъл';
UPDATE `promenliviprevodi` SET `du` = 'Shuma minimale për këtë kod: {amount}' WHERE `id` = 3257 AND `du` = 'Минимална сума за код: {amount}';
UPDATE `promenliviprevodi` SET `du` = 'Kodi është aplikuar tashmë' WHERE `id` = 3258 AND `du` = 'Кодът вече е приложен';
UPDATE `promenliviprevodi` SET `du` = 'Kërkesë e pavlefshme' WHERE `id` = 3259 AND `du` = 'Невалидна заявка';
UPDATE `promenliviprevodi` SET `du` = 'Sesion i pavlefshëm' WHERE `id` = 3260 AND `du` = 'Невалидна сесия';
UPDATE `promenliviprevodi` SET `du` = 'Kodi promocional {code} u hoq — shuma minimale për të është {amount}.' WHERE `id` = 3261 AND `du` = 'Промо кодът {code} беше премахнат — минималната сума за него е {amount}.';
UPDATE `promenliviprevodi` SET `du` = 'Kodi promocional {code} ka skaduar dhe u hoq.' WHERE `id` = 3262 AND `du` = 'Промо кодът {code} е изтекъл и беше премахнат.';
UPDATE `promenliviprevodi` SET `du` = 'Kodi promocional {code} nuk vlen për këtë faqe dhe u hoq.' WHERE `id` = 3263 AND `du` = 'Промо кодът {code} не важи за този сайт и беше премахнат.';
UPDATE `promenliviprevodi` SET `du` = 'Kodi promocional {code} është shteruar dhe u hoq.' WHERE `id` = 3264 AND `du` = 'Промо кодът {code} е изчерпан и беше премахнат.';
UPDATE `promenliviprevodi` SET `du` = 'Kodi promocional {code} nuk është më aktiv dhe u hoq.' WHERE `id` = 3265 AND `du` = 'Промо кодът {code} вече не е активен и беше премахнат.';
