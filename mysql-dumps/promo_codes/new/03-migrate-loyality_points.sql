-- =============================================================================
-- 03 — Migrate loyality_points → promo_codes
-- Target: imartap
-- INSERT IGNORE skips code collisions. Filters: kod non-empty, tip IN (0,1,2).
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
   1,
   IF(izpolzvan = '1', 0, 1),
   data_validen,
   data_sazdaden,
   data_izpolzvan,
   'the-marketer',
   komentar,
   sait,
   COALESCE(NULLIF(ot_kade, ''), 'the-marketer')
FROM loyality_points
WHERE kod IS NOT NULL AND kod <> ''
  AND tip IN (0, 1, 2)
  AND sait IN ('bg', 'ro', 'gr');
