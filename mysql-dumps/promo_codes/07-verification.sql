-- =============================================================================
-- Post-migration verification
-- =============================================================================
-- Изпълни СЛЕД 05 и 06. Сравнява counts и spot-проверки между старите
-- таблици и новата promo_codes.
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

-- Mismatches — кодове в старите таблици, които НЕ са в promo_codes
SELECT 'missing from loyality' AS lbl, l.id, l.kod
  FROM loyality_points l
  LEFT JOIN promo_codes p ON p.code = l.kod
  WHERE p.id IS NULL AND l.kod IS NOT NULL AND l.kod <> ''
UNION ALL
SELECT 'missing from obshti' AS lbl, o.id, o.kod
  FROM obshti_kodove o
  LEFT JOIN promo_codes p ON p.code = o.kod
  WHERE p.id IS NULL AND o.kod IS NOT NULL AND o.kod <> '';

-- Spot checks — известни кодове
SELECT id, code, type, discount_value, voucher_remainer, max_uses, active,
       expiration_date, created_at, used_at, source, created_by, note
FROM promo_codes
WHERE code IN ('VELIKDEN10','slujeben10','SPRING10EM26','svet25evro','svet10procenta','kod0','kod1')
ORDER BY source, code;

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

-- Sanity: voucher_remainer само за fixed type
SELECT 'voucher_remainer set for non-fixed' AS lbl, COUNT(*) AS cnt
FROM promo_codes
WHERE voucher_remainer IS NOT NULL AND type <> 'fixed';
-- Очаквано: 0

-- Sanity: всеки fixed type има voucher_remainer
SELECT 'fixed type without voucher_remainer' AS lbl, COUNT(*) AS cnt
FROM promo_codes
WHERE type = 'fixed' AND voucher_remainer IS NULL;
-- Очаквано: 0

-- Sanity: created_at винаги е попълнен (NOT NULL constraint)
SELECT 'rows missing created_at' AS lbl, COUNT(*) AS cnt
FROM promo_codes
WHERE created_at IS NULL OR created_at = '';
-- Очаквано: 0

-- Compare value field-by-field за случайна извадка от 5 кода
SELECT
   l.kod                            AS source_kod,
   l.tip                            AS source_tip,
   l.value                          AS source_value,
   p.code                           AS promo_code,
   p.type                           AS promo_type,
   p.discount_value                 AS promo_discount,
   p.voucher_remainer               AS promo_voucher,
   p.source                         AS promo_source
FROM loyality_points l
JOIN promo_codes p ON p.code = l.kod
ORDER BY l.id
LIMIT 5;
