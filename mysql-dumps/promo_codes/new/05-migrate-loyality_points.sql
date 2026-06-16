-- =============================================================================
-- Migration: loyality_points → promo_codes
-- =============================================================================
-- Прехвърля single-use The Marketer codes. Задава:
--   max_uses         = 1
--   source           = 'the-marketer'
--   active           = NOT izpolzvan (вече използваните стават неактивни)
--   used_at          = data_izpolzvan (last-used timestamp)
--   created_by       = ot_kade ИЛИ 'the-marketer' (ако е празно)
--
-- INSERT IGNORE — пропуска редове, които биха нарушили UNIQUE на code.
-- WHERE tip IN (0,1,2) — изключва NULL/невалидни tip стойности.
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
   1,                                              -- single-use
   IF(izpolzvan = '1', 0, 1),                      -- използваният → неактивен
   data_validen,
   data_sazdaden,
   data_izpolzvan,
   'the-marketer',
   komentar,
   sait,
   COALESCE(NULLIF(ot_kade, ''), 'the-marketer')
FROM loyality_points
WHERE kod IS NOT NULL AND kod <> ''
  AND tip IN (0, 1, 2);
