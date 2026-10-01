-- =============================================================================
-- 23 ROLLBACK — връща 23-prevodi-promo-al.sql обратно на български (3101–3108, 3250–3265)
-- Target: САМО al регионалната база.
-- Run: mysql -D <al_db> --default-character-set=utf8mb4 < 23-prevodi-promo-al-rollback.sql
--
-- Огледален на 23-prevodi-promo-al.sql: SET и WHERE са разменени. Резултатът е
-- seed-натият български от 20 и 21 — промо UI-ът изглежда както преди 23.
--
-- `AND du = '<албански>'`: пипа само ред, който още е точно текстът от 23.
-- Ред, редактиран от преводач след 23, остава. Повторно пускане е no-op.
--
-- Проверка след пускане (очаквано: 24):
--     SELECT COUNT(*) FROM promenliviprevodi
--     WHERE (id BETWEEN 3101 AND 3108 OR id BETWEEN 3250 AND 3265)
--       AND du REGEXP '[А-Яа-я]';
--   По-малко = някой ред е бил редактиран ръчно след 23; виж го на ръка.
-- =============================================================================

SET NAMES utf8mb4;

UPDATE `promenliviprevodi` SET `du` = 'Въведи промо код' WHERE `id` = 3101 AND `du` = 'Vendosni kodin promocional';
UPDATE `promenliviprevodi` SET `du` = 'Приложи' WHERE `id` = 3102 AND `du` = 'Apliko';
UPDATE `promenliviprevodi` SET `du` = 'Безплатна доставка' WHERE `id` = 3103 AND `du` = 'Transport falas';
UPDATE `promenliviprevodi` SET `du` = 'до' WHERE `id` = 3104 AND `du` = 'deri në';
UPDATE `promenliviprevodi` SET `du` = 'Грешка при свързване' WHERE `id` = 3105 AND `du` = 'Gabim në lidhje';
UPDATE `promenliviprevodi` SET `du` = 'Промо код' WHERE `id` = 3106 AND `du` = 'Kod promocional';
UPDATE `promenliviprevodi` SET `du` = '(доставка)' WHERE `id` = 3107 AND `du` = '(transporti)';
UPDATE `promenliviprevodi` SET `du` = 'Отстъпка за доставка' WHERE `id` = 3108 AND `du` = 'Zbritje për transportin';
UPDATE `promenliviprevodi` SET `du` = 'Невалиден код' WHERE `id` = 3250 AND `du` = 'Kod i pavlefshëm';
UPDATE `promenliviprevodi` SET `du` = 'Количката е празна' WHERE `id` = 3251 AND `du` = 'Shporta është bosh';
UPDATE `promenliviprevodi` SET `du` = 'Временна грешка, опитай пак' WHERE `id` = 3252 AND `du` = 'Gabim i përkohshëm, provoni përsëri';
UPDATE `promenliviprevodi` SET `du` = 'Не може да се комбинира с вече приложен код от същата група' WHERE `id` = 3253 AND `du` = 'Nuk mund të kombinohet me një kod tashmë të aplikuar nga i njëjti grup';
UPDATE `promenliviprevodi` SET `du` = 'Кодът е изчерпан' WHERE `id` = 3254 AND `du` = 'Kodi është shteruar';
UPDATE `promenliviprevodi` SET `du` = 'Кодът не е активен' WHERE `id` = 3255 AND `du` = 'Kodi nuk është aktiv';
UPDATE `promenliviprevodi` SET `du` = 'Кодът е изтекъл' WHERE `id` = 3256 AND `du` = 'Kodi ka skaduar';
UPDATE `promenliviprevodi` SET `du` = 'Минимална сума за код: {amount}' WHERE `id` = 3257 AND `du` = 'Shuma minimale për këtë kod: {amount}';
UPDATE `promenliviprevodi` SET `du` = 'Кодът вече е приложен' WHERE `id` = 3258 AND `du` = 'Kodi është aplikuar tashmë';
UPDATE `promenliviprevodi` SET `du` = 'Невалидна заявка' WHERE `id` = 3259 AND `du` = 'Kërkesë e pavlefshme';
UPDATE `promenliviprevodi` SET `du` = 'Невалидна сесия' WHERE `id` = 3260 AND `du` = 'Sesion i pavlefshëm';
UPDATE `promenliviprevodi` SET `du` = 'Промо кодът {code} беше премахнат — минималната сума за него е {amount}.' WHERE `id` = 3261 AND `du` = 'Kodi promocional {code} u hoq — shuma minimale për të është {amount}.';
UPDATE `promenliviprevodi` SET `du` = 'Промо кодът {code} е изтекъл и беше премахнат.' WHERE `id` = 3262 AND `du` = 'Kodi promocional {code} ka skaduar dhe u hoq.';
UPDATE `promenliviprevodi` SET `du` = 'Промо кодът {code} не важи за този сайт и беше премахнат.' WHERE `id` = 3263 AND `du` = 'Kodi promocional {code} nuk vlen për këtë faqe dhe u hoq.';
UPDATE `promenliviprevodi` SET `du` = 'Промо кодът {code} е изчерпан и беше премахнат.' WHERE `id` = 3264 AND `du` = 'Kodi promocional {code} është shteruar dhe u hoq.';
UPDATE `promenliviprevodi` SET `du` = 'Промо кодът {code} вече не е активен и беше премахнат.' WHERE `id` = 3265 AND `du` = 'Kodi promocional {code} nuk është më aktiv dhe u hoq.';
