-- =============================================================================
-- 05 — Post-migration verification (imartap)
-- Target: imartap
-- Read-only: only SELECTs
-- =============================================================================

USE imartap;

-- Counts overview
SELECT
   (SELECT COUNT(*) FROM loyality_points)                         AS loyality_total,
   (SELECT COUNT(*) FROM obshti_kodove)                           AS obshti_total,
   (SELECT COUNT(*) FROM promo_codes)                             AS promo_total,
   (SELECT COUNT(*) FROM promo_codes WHERE source='the-marketer') AS from_marketer,
   (SELECT COUNT(*) FROM promo_codes WHERE source='manual')       AS from_manual;

-- Codes in source tables missing from promo_codes (expect 0 rows)
SELECT 'missing from loyality' AS lbl, l.id, l.kod
FROM loyality_points l
LEFT JOIN promo_codes p ON p.code = l.kod
WHERE p.id IS NULL AND l.kod IS NOT NULL AND l.kod <> '' AND l.tip IN (0,1,2)
UNION ALL
SELECT 'missing from obshti', o.id, o.kod
FROM obshti_kodove o
LEFT JOIN promo_codes p ON p.code = o.kod
WHERE p.id IS NULL AND o.kod IS NOT NULL AND o.kod <> '' AND o.tip IN (0,1,2);

-- Type/source distribution
SELECT source, type, COUNT(*) AS cnt
FROM promo_codes
GROUP BY source, type
ORDER BY source, type;

-- Schema sanity: correct columns present
SELECT COLUMN_NAME, COLUMN_TYPE
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'imartap' AND TABLE_NAME = 'promo_codes'
  AND COLUMN_NAME IN ('type','subtype','shipping_cap','times_used')
ORDER BY COLUMN_NAME;
