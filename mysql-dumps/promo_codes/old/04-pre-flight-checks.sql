-- =============================================================================
-- Pre-flight diagnostic queries
-- =============================================================================
-- Изпълни ПРЕДИ migration. На база резултатите решаваме:
--
-- 1. Ако кодове > 50 символа → вдигаме promo_codes.code лимита.
-- 2. Ако има NULL/невалидни tip → migration вече ги филтрира с WHERE tip IN (0,1,2).
-- 3. Ако има collisions между двете таблици → INSERT IGNORE ще ги изхвърли;
--    важно е да знаем колко са, за да решим кои да pre-empt-нем.
-- 4. Ако има празни kod → migration ги филтрира с WHERE kod IS NOT NULL AND kod <> ''.
-- 5. Ако има невалиден формат на data_validen → може да трябва ръчно
--    почистване преди миграцията.
-- 6. Baseline counts — за сравнение след миграцията.
-- =============================================================================

USE imartap;

-- 1. Кодове по-дълги от 50 символа?
SELECT 'loyality_points' AS tbl, MAX(LENGTH(kod)) AS max_len, COUNT(*) AS total FROM loyality_points
UNION ALL
SELECT 'obshti_kodove'    AS tbl, MAX(LENGTH(kod)) AS max_len, COUNT(*) AS total FROM obshti_kodove;

-- 2. NULL или невалидни tip стойности
SELECT 'loyality NULL/bad tip' AS lbl, COUNT(*) AS cnt FROM loyality_points WHERE tip IS NULL OR tip NOT IN (0,1,2)
UNION ALL
SELECT 'obshti NULL/bad tip'    AS lbl, COUNT(*) AS cnt FROM obshti_kodove   WHERE tip IS NULL OR tip NOT IN (0,1,2);

-- 3. Code collisions между двете таблици
SELECT l.kod AS colliding_code,
       l.id  AS loyality_id,
       o.id  AS obshti_id
FROM loyality_points l
JOIN obshti_kodove o ON l.kod = o.kod;

-- 4. Невалидни (празни/NULL) кодове
SELECT 'loyality empty kod' AS lbl, COUNT(*) AS cnt FROM loyality_points WHERE kod IS NULL OR kod = ''
UNION ALL
SELECT 'obshti empty kod'    AS lbl, COUNT(*) AS cnt FROM obshti_kodove   WHERE kod IS NULL OR kod = '';

-- 5. data_validen формат — всички ли са 14-цифрен YYYYMMDDHHmmss
SELECT 'loyality bad date' AS lbl, COUNT(*) AS cnt FROM loyality_points
  WHERE data_validen IS NOT NULL
    AND (LENGTH(data_validen) <> 14 OR data_validen NOT REGEXP '^[0-9]{14}$')
UNION ALL
SELECT 'obshti bad date'    AS lbl, COUNT(*) AS cnt FROM obshti_kodove
  WHERE data_validen IS NOT NULL
    AND (LENGTH(data_validen) <> 14 OR data_validen NOT REGEXP '^[0-9]{14}$');

-- 6. Baseline counts
SELECT 'loyality_points'      AS tbl, COUNT(*) AS total FROM loyality_points
UNION ALL
SELECT 'obshti_kodove'        AS tbl, COUNT(*) AS total FROM obshti_kodove
UNION ALL
SELECT 'promo_codes (before)' AS tbl, COUNT(*) AS total FROM promo_codes;
