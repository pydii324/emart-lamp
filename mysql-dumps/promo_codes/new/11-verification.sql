-- =============================================================================
-- Verification (imartap) — data migration + финална schema, след 01–08
-- =============================================================================
-- Само SELECT-и. Изпълнява се директно срещу imartap.
-- Per-DB проверките (регионалните бази) са в 10-verify-per-db.sql.
-- =============================================================================

USE imartap;

-- Aggregate counts — overview
SELECT
   (SELECT COUNT(*) FROM loyality_points)                          AS loyality_total,
   (SELECT COUNT(*) FROM obshti_kodove)                            AS obshti_total,
   (SELECT COUNT(*) FROM promo_codes)                              AS promo_total,
   (SELECT COUNT(*) FROM promo_codes WHERE source='the-marketer')  AS from_marketer,
   (SELECT COUNT(*) FROM promo_codes WHERE source='manual')        AS from_manual,
   (SELECT COUNT(*) FROM promo_codes WHERE source='bulk-import')   AS from_bulk;
-- Очаквано: promo_total ≈ loyality_total + obshti_total − duplicates − invalid_tip_rows
-- Reference run (2026-05): 16235 = 16221 + 14

-- Mismatches — кодове в старите таблици, които НЕ са в promo_codes
SELECT 'missing from loyality' AS lbl, l.id, l.kod
  FROM loyality_points l
  LEFT JOIN promo_codes p ON p.code = l.kod
  WHERE p.id IS NULL AND l.kod IS NOT NULL AND l.kod <> ''
UNION ALL
SELECT 'missing from obshti' AS lbl, o.id, o.kod
  FROM obshti_kodove o
  LEFT JOIN promo_codes p ON p.code = o.kod
  WHERE p.id IS NULL AND o.kod IS NOT NULL AND o.kod <> '' AND o.tip IN (0,1,2);
-- Очаквано: 0 реда

-- Type distribution по източник
SELECT source, type, COUNT(*) AS cnt
FROM promo_codes
GROUP BY source, type
ORDER BY source, type;

-- Active distribution по източник
SELECT source, active, COUNT(*) AS cnt
FROM promo_codes
GROUP BY source, active
ORDER BY source, active;

-- Sanity: created_at винаги е попълнен (NOT NULL constraint)
SELECT 'rows missing created_at' AS lbl, COUNT(*) AS cnt
FROM promo_codes
WHERE created_at IS NULL OR created_at = '';
-- Очаквано: 0

-- Schema sanity: финалните колони ги има, междинните ги няма
SELECT 'has times_used'                AS lbl, COUNT(*) AS cnt FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA='imartap' AND TABLE_NAME='promo_codes' AND COLUMN_NAME='times_used'
UNION ALL
SELECT 'has used_by_employeeId (opc)'  AS lbl, COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA='imartap' AND TABLE_NAME='order_promo_codes' AND COLUMN_NAME='used_by_employeeId'
UNION ALL
SELECT 'NO max_uses_per_user (legacy)' AS lbl, COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA='imartap' AND TABLE_NAME='promo_codes' AND COLUMN_NAME='max_uses_per_user'
UNION ALL
SELECT 'NO voucher_remainer (burned)' AS lbl, COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA='imartap' AND TABLE_NAME='promo_codes' AND COLUMN_NAME='voucher_remainer';
-- Очаквано: 1 / 1 / 0 / 0

-- Compare value field-by-field за извадка от 5 кода
SELECT
   l.kod    AS source_kod,
   l.tip    AS source_tip,
   l.value  AS source_value,
   p.code   AS promo_code,
   p.type   AS promo_type,
   p.discount_value AS promo_discount,
   p.source AS promo_source
FROM loyality_points l
JOIN promo_codes p ON p.code = l.kod
ORDER BY l.id
LIMIT 5;
