-- =============================================================================
-- 22 ROLLBACK — връща 22-prevodi-promo-ro.sql обратно на български (3101–3108, 3250–3265)
-- Target: САМО ro регионалната база.
-- Run: mysql -D <ro_db> --default-character-set=utf8mb4 < 22-prevodi-promo-ro-rollback.sql
--
-- Огледален на 22-prevodi-promo-ro.sql: SET и WHERE са разменени. Резултатът е
-- seed-натият български от 20 и 21 — промо UI-ът изглежда както преди 22.
--
-- `AND du = '<румънски>'`: пипа само ред, който още е точно текстът от 22.
-- Ред, редактиран от преводач след 22, остава. Повторно пускане е no-op.
--
-- Проверка след пускане (очаквано: 24):
--     SELECT COUNT(*) FROM promenliviprevodi
--     WHERE (id BETWEEN 3101 AND 3108 OR id BETWEEN 3250 AND 3265)
--       AND du REGEXP '[А-Яа-я]';
--   По-малко = някой ред е бил редактиран ръчно след 22; виж го на ръка.
-- =============================================================================

SET NAMES utf8mb4;

UPDATE `promenliviprevodi` SET `du` = 'Въведи промо код' WHERE `id` = 3101 AND `du` = 'Introduceți codul promoțional';
UPDATE `promenliviprevodi` SET `du` = 'Приложи' WHERE `id` = 3102 AND `du` = 'Aplică';
UPDATE `promenliviprevodi` SET `du` = 'Безплатна доставка' WHERE `id` = 3103 AND `du` = 'Livrare gratuită';
UPDATE `promenliviprevodi` SET `du` = 'до' WHERE `id` = 3104 AND `du` = 'până la';
UPDATE `promenliviprevodi` SET `du` = 'Грешка при свързване' WHERE `id` = 3105 AND `du` = 'Eroare de conexiune';
UPDATE `promenliviprevodi` SET `du` = 'Промо код' WHERE `id` = 3106 AND `du` = 'Cod promoțional';
UPDATE `promenliviprevodi` SET `du` = '(доставка)' WHERE `id` = 3107 AND `du` = '(livrare)';
UPDATE `promenliviprevodi` SET `du` = 'Отстъпка за доставка' WHERE `id` = 3108 AND `du` = 'Reducere la livrare';
UPDATE `promenliviprevodi` SET `du` = 'Невалиден код' WHERE `id` = 3250 AND `du` = 'Cod invalid';
UPDATE `promenliviprevodi` SET `du` = 'Количката е празна' WHERE `id` = 3251 AND `du` = 'Coșul este gol';
UPDATE `promenliviprevodi` SET `du` = 'Временна грешка, опитай пак' WHERE `id` = 3252 AND `du` = 'Eroare temporară, încercați din nou';
UPDATE `promenliviprevodi` SET `du` = 'Не може да се комбинира с вече приложен код от същата група' WHERE `id` = 3253 AND `du` = 'Nu poate fi combinat cu un cod deja aplicat din același grup';
UPDATE `promenliviprevodi` SET `du` = 'Кодът е изчерпан' WHERE `id` = 3254 AND `du` = 'Codul a fost epuizat';
UPDATE `promenliviprevodi` SET `du` = 'Кодът не е активен' WHERE `id` = 3255 AND `du` = 'Codul nu este activ';
UPDATE `promenliviprevodi` SET `du` = 'Кодът е изтекъл' WHERE `id` = 3256 AND `du` = 'Codul a expirat';
UPDATE `promenliviprevodi` SET `du` = 'Минимална сума за код: {amount}' WHERE `id` = 3257 AND `du` = 'Suma minimă pentru acest cod: {amount}';
UPDATE `promenliviprevodi` SET `du` = 'Кодът вече е приложен' WHERE `id` = 3258 AND `du` = 'Codul a fost deja aplicat';
UPDATE `promenliviprevodi` SET `du` = 'Невалидна заявка' WHERE `id` = 3259 AND `du` = 'Cerere invalidă';
UPDATE `promenliviprevodi` SET `du` = 'Невалидна сесия' WHERE `id` = 3260 AND `du` = 'Sesiune invalidă';
UPDATE `promenliviprevodi` SET `du` = 'Промо кодът {code} беше премахнат — минималната сума за него е {amount}.' WHERE `id` = 3261 AND `du` = 'Codul promoțional {code} a fost eliminat — suma minimă pentru el este {amount}.';
UPDATE `promenliviprevodi` SET `du` = 'Промо кодът {code} е изтекъл и беше премахнат.' WHERE `id` = 3262 AND `du` = 'Codul promoțional {code} a expirat și a fost eliminat.';
UPDATE `promenliviprevodi` SET `du` = 'Промо кодът {code} не важи за този сайт и беше премахнат.' WHERE `id` = 3263 AND `du` = 'Codul promoțional {code} nu este valabil pentru acest site și a fost eliminat.';
UPDATE `promenliviprevodi` SET `du` = 'Промо кодът {code} е изчерпан и беше премахнат.' WHERE `id` = 3264 AND `du` = 'Codul promoțional {code} a fost epuizat și a fost eliminat.';
UPDATE `promenliviprevodi` SET `du` = 'Промо кодът {code} вече не е активен и беше премахнат.' WHERE `id` = 3265 AND `du` = 'Codul promoțional {code} nu mai este activ și a fost eliminat.';
