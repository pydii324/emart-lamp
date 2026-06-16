-- =============================================================================
-- Migration: obshti_kodove → promo_codes
-- =============================================================================
-- Прехвърля multi-use manual codes. Задава:
--   max_uses         = 0 (безлимит)
--   source           = 'manual'
--   active           = IF(data_validen > NOW, 1, 0) — изтеклите автоматично
--                      стават неактивни (решение от Step 0, виж
--                      promo-codes-execution-log.md)
--   used_at          = NULL (obshti_kodove няма last-used timestamp; само counter)
--   created_by       = ot_kade (може да е празно)
--
-- INSERT IGNORE — пропуска редове, които биха нарушили UNIQUE на code
-- (важно когато същи код е дошъл от loyality_points в стъпка 05).
-- WHERE tip IN (0,1,2) — изключва NULL/невалидни tip стойности (test редове).
-- =============================================================================

USE imartap;

INSERT IGNORE INTO promo_codes
  (code, type, discount_value,
   max_uses, active,
   expiration_date, created_at, used_at,
   source, note, site, created_by)
SELECT
   kod,
   CASE tip WHEN 0 THEN 'fixed' WHEN 1 THEN 'percent' WHEN 2 THEN 'shipping' ELSE 'percent' END,
   CAST(value AS DECIMAL(10,2)),
   0,                                              -- multi-use (безлимит)
   IF(data_validen IS NULL OR data_validen > DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 1, 0),
   data_validen,
   data_sazdaden,
   NULL,                                           -- няма last-used в obshti_kodove
   'manual',
   komentar,
   sait,
   NULLIF(ot_kade, '')
FROM obshti_kodove
WHERE kod IS NOT NULL AND kod <> ''
  AND tip IN (0, 1, 2);
