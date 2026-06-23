-- =============================================================================
-- 04 — Migrate obshti_kodove → promo_codes
-- Target: imartap
-- INSERT IGNORE skips collisions (same code already from loyality_points).
-- Expired codes (data_validen < NOW) are inserted as active=0.
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
   0,
   IF(data_validen IS NULL OR data_validen > DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 1, 0),
   data_validen,
   data_sazdaden,
   NULL,
   'manual',
   komentar,
   sait,
   NULLIF(ot_kade, '')
FROM obshti_kodove
WHERE kod IS NOT NULL AND kod <> ''
  AND tip IN (0, 1, 2)
  AND sait IN ('bg', 'ro', 'gr');
