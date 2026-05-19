-- =============================================================================
-- Migration: obshti_kodove → promo_codes
-- =============================================================================
-- Прехвърля multi-use manual codes. Задава:
--   max_uses         = 0 (безлимит)
--   source           = 'manual'
--   active           = 1 (всички; виж OPEN DECISION по-долу)
--   voucher_remainer = value (само за fixed type)
--   used_at          = NULL (obshti_kodove няма last-used timestamp; само counter)
--   created_by       = ot_kade (може да е празно)
--
-- INSERT IGNORE — пропуска редове, които биха нарушили UNIQUE на code
-- (важно когато същи код е дошъл от loyality_points в стъпка 05).
--
-- ОТВОРЕНО РЕШЕНИЕ за active:
--   Текущо: active = 1 за всички, дори за изтекли.
--   Алтернатива: IF(data_validen > DATE_FORMAT(NOW(),'%Y%m%d%H%i%s'), 1, 0)
--   — деактивира експлицитно изтеклите.
-- =============================================================================

USE imartap;

INSERT IGNORE INTO promo_codes
  (code, type, discount_value, voucher_remainer,
   max_uses, active,
   expiration_date, created_at, used_at,
   source, note, site, created_by)
SELECT
   kod,
   CASE tip WHEN 0 THEN 'fixed' WHEN 1 THEN 'percent' WHEN 2 THEN 'shipping' ELSE 'percent' END,
   CAST(value AS DECIMAL(10,2)),
   CASE WHEN tip = 0 THEN CAST(value AS DECIMAL(10,2)) ELSE NULL END,
   0,                                              -- multi-use (безлимит)
   1,                                              -- active; виж OPEN DECISION
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
