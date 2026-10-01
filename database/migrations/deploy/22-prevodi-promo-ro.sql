-- =============================================================================
-- 22 — promenliviprevodi: промо кодовете на румънски (3101–3108, 3250–3265)
-- Target: САМО ro регионалната база.
-- Run: mysql -D <ro_db> --default-character-set=utf8mb4 < 22-prevodi-promo-ro.sql
-- Prereq: 20-seed-promo-prevodi.sql и 21-seed-promo-prevodi-errors.sql на същата база.
--
-- WHY: seed 20 и 21 слагат български текст навсякъде, така че ro сайтът
-- показваше „Невалиден код" (QA #48). Тук идва текстът на румънски.
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

UPDATE `promenliviprevodi` SET `du` = 'Introduceți codul promoțional' WHERE `id` = 3101 AND `du` = 'Въведи промо код';
UPDATE `promenliviprevodi` SET `du` = 'Aplică' WHERE `id` = 3102 AND `du` = 'Приложи';
UPDATE `promenliviprevodi` SET `du` = 'Livrare gratuită' WHERE `id` = 3103 AND `du` = 'Безплатна доставка';
UPDATE `promenliviprevodi` SET `du` = 'până la' WHERE `id` = 3104 AND `du` = 'до';
UPDATE `promenliviprevodi` SET `du` = 'Eroare de conexiune' WHERE `id` = 3105 AND `du` = 'Грешка при свързване';
UPDATE `promenliviprevodi` SET `du` = 'Cod promoțional' WHERE `id` = 3106 AND `du` = 'Промо код';
UPDATE `promenliviprevodi` SET `du` = '(livrare)' WHERE `id` = 3107 AND `du` = '(доставка)';
UPDATE `promenliviprevodi` SET `du` = 'Reducere la livrare' WHERE `id` = 3108 AND `du` = 'Отстъпка за доставка';
UPDATE `promenliviprevodi` SET `du` = 'Cod invalid' WHERE `id` = 3250 AND `du` = 'Невалиден код';
UPDATE `promenliviprevodi` SET `du` = 'Coșul este gol' WHERE `id` = 3251 AND `du` = 'Количката е празна';
UPDATE `promenliviprevodi` SET `du` = 'Eroare temporară, încercați din nou' WHERE `id` = 3252 AND `du` = 'Временна грешка, опитай пак';
UPDATE `promenliviprevodi` SET `du` = 'Nu poate fi combinat cu un cod deja aplicat din același grup' WHERE `id` = 3253 AND `du` = 'Не може да се комбинира с вече приложен код от същата група';
UPDATE `promenliviprevodi` SET `du` = 'Codul a fost epuizat' WHERE `id` = 3254 AND `du` = 'Кодът е изчерпан';
UPDATE `promenliviprevodi` SET `du` = 'Codul nu este activ' WHERE `id` = 3255 AND `du` = 'Кодът не е активен';
UPDATE `promenliviprevodi` SET `du` = 'Codul a expirat' WHERE `id` = 3256 AND `du` = 'Кодът е изтекъл';
UPDATE `promenliviprevodi` SET `du` = 'Suma minimă pentru acest cod: {amount}' WHERE `id` = 3257 AND `du` = 'Минимална сума за код: {amount}';
UPDATE `promenliviprevodi` SET `du` = 'Codul a fost deja aplicat' WHERE `id` = 3258 AND `du` = 'Кодът вече е приложен';
UPDATE `promenliviprevodi` SET `du` = 'Cerere invalidă' WHERE `id` = 3259 AND `du` = 'Невалидна заявка';
UPDATE `promenliviprevodi` SET `du` = 'Sesiune invalidă' WHERE `id` = 3260 AND `du` = 'Невалидна сесия';
UPDATE `promenliviprevodi` SET `du` = 'Codul promoțional {code} a fost eliminat — suma minimă pentru el este {amount}.' WHERE `id` = 3261 AND `du` = 'Промо кодът {code} беше премахнат — минималната сума за него е {amount}.';
UPDATE `promenliviprevodi` SET `du` = 'Codul promoțional {code} a expirat și a fost eliminat.' WHERE `id` = 3262 AND `du` = 'Промо кодът {code} е изтекъл и беше премахнат.';
UPDATE `promenliviprevodi` SET `du` = 'Codul promoțional {code} nu este valabil pentru acest site și a fost eliminat.' WHERE `id` = 3263 AND `du` = 'Промо кодът {code} не важи за този сайт и беше премахнат.';
UPDATE `promenliviprevodi` SET `du` = 'Codul promoțional {code} a fost epuizat și a fost eliminat.' WHERE `id` = 3264 AND `du` = 'Промо кодът {code} е изчерпан и беше премахнат.';
UPDATE `promenliviprevodi` SET `du` = 'Codul promoțional {code} nu mai este activ și a fost eliminat.' WHERE `id` = 3265 AND `du` = 'Промо кодът {code} вече не е активен и беше премахнат.';
