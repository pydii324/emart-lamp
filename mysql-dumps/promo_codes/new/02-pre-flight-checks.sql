-- =============================================================================
-- 02 — Pre-flight diagnostic queries (run BEFORE data migration)
-- Target: imartap
-- Read-only: only SELECTs
-- =============================================================================

USE imartap;

-- Code length: ensure none exceed VARCHAR(50)
SELECT 'loyality_points' AS tbl, MAX(LENGTH(kod)) AS max_len, COUNT(*) AS total FROM loyality_points
UNION ALL
SELECT 'obshti_kodove',          MAX(LENGTH(kod)),             COUNT(*) FROM obshti_kodove;

-- Invalid tip values (will be excluded from migration)
SELECT 'loyality NULL/bad tip' AS lbl, COUNT(*) AS cnt FROM loyality_points WHERE tip IS NULL OR tip NOT IN (0,1,2)
UNION ALL
SELECT 'obshti NULL/bad tip',   COUNT(*) FROM obshti_kodove WHERE tip IS NULL OR tip NOT IN (0,1,2);

-- Code collisions between source tables (INSERT IGNORE will skip these)
SELECT l.kod AS colliding_code, l.id AS loyality_id, o.id AS obshti_id
FROM loyality_points l
JOIN obshti_kodove o ON l.kod = o.kod;

-- Empty/NULL codes (will be excluded)
SELECT 'loyality empty kod' AS lbl, COUNT(*) AS cnt FROM loyality_points WHERE kod IS NULL OR kod = ''
UNION ALL
SELECT 'obshti empty kod',   COUNT(*) FROM obshti_kodove WHERE kod IS NULL OR kod = '';

-- Baseline counts
SELECT 'loyality_points'      AS tbl, COUNT(*) AS total FROM loyality_points
UNION ALL
SELECT 'obshti_kodove',               COUNT(*) FROM obshti_kodove
UNION ALL
SELECT 'promo_codes (before)',         COUNT(*) FROM promo_codes;
