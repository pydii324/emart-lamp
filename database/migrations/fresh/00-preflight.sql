-- =============================================================================
-- 00 — PRE-FLIGHT (read-only, writes NOTHING)
-- Target: EVERY DB you are about to migrate — regional AND imartap.
-- Run: mysql -D <db> --table < 00-preflight.sql
--
-- The rest of this set is plain, unguarded SQL: the first bad statement aborts the
-- file and leaves the earlier statements applied. This file proves up-front that
-- the target really is a from-zero environment, so that never happens.
--
-- EVERY row of every check must read OK. A single FAIL means this DB is NOT a
-- fresh target — it has been through the historical migration path (or a partial
-- fresh run). Do NOT continue; reconcile by hand or use ../../deploy/* instead.
--
-- The checks are written against information_schema, so a missing table is simply
-- a zero count, not an error — a regional DB legitimately has no `porachki` master
-- and imartap legitimately has no `item_l`/`item_no`/`catalog`. Those show up as
-- "n/a (table absent here)", which is NOT a failure.
-- =============================================================================

SELECT DATABASE() AS `db`, VERSION() AS `mysql_version`, NOW() AS `checked_at`;


-- ── 1. Which of the tables this set touches exist here? ──────────────────────
-- Tells you which target you are on. Regional expects: catalog, item, item_l,
-- item_no, porachki, porachki_l, porachki_no. imartap expects: item, porachki.
SELECT
  'A. tables present' AS `check`,
  TABLE_NAME          AS `table`,
  TABLE_ROWS          AS `approx_rows`
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('catalog','item','item_l','item_no',
                     'porachki','porachki_l','porachki_no')
ORDER BY TABLE_NAME;


-- ── 2. None of the promo tables may exist yet ────────────────────────────────
-- Created by 01/02 (regional) and 06/07/09 (imartap).
SELECT
  'B. promo tables absent' AS `check`,
  t.`name`                 AS `table`,
  IF(c.TABLE_NAME IS NULL, 'OK', 'FAIL — already exists') AS `result`
FROM (
  SELECT 'promo_codes' AS `name`
  UNION ALL SELECT 'cart_promo_codes'
  UNION ALL SELECT 'order_promo_codes'
  UNION ALL SELECT 'currency_rates'
) t
LEFT JOIN information_schema.TABLES c
       ON c.TABLE_SCHEMA = DATABASE()
      AND c.TABLE_NAME   = t.`name`
ORDER BY t.`name`;


-- ── 3. item* baseline: ORIGINAL stored it_cena / it_suma ─────────────────────
-- File 03 is additive on top of these. On a DB that went through the historical
-- path they are VIRTUAL generated columns (EXTRA contains 'GENERATED') — that is
-- the single clearest tell that this is NOT a fresh target.
SELECT
  'C. it_cena/it_suma are original stored cols' AS `check`,
  t.`name`     AS `table`,
  t.`col`      AS `column`,
  CASE
    WHEN tt.TABLE_NAME IS NULL         THEN 'n/a (table absent here)'
    WHEN col.COLUMN_NAME IS NULL       THEN 'FAIL — column missing'
    WHEN col.EXTRA LIKE '%GENERATED%'  THEN CONCAT('FAIL — generated: ', col.EXTRA)
    ELSE CONCAT('OK — stored ', col.COLUMN_TYPE)
  END AS `result`
FROM (
            SELECT 'item'    AS `name`, 'it_cena' AS `col`
  UNION ALL SELECT 'item',              'it_suma'
  UNION ALL SELECT 'item_l',            'it_cena'
  UNION ALL SELECT 'item_l',            'it_suma'
  UNION ALL SELECT 'item_no',           'it_cena'
  UNION ALL SELECT 'item_no',           'it_suma'
) t
LEFT JOIN information_schema.TABLES tt
       ON tt.TABLE_SCHEMA = DATABASE()
      AND tt.TABLE_NAME   = t.`name`
LEFT JOIN information_schema.COLUMNS col
       ON col.TABLE_SCHEMA = DATABASE()
      AND col.TABLE_NAME   = t.`name`
      AND col.COLUMN_NAME  = t.`col`
ORDER BY t.`name`, t.`col`;


-- ── 4. No leftovers from the historical path, no promo columns yet ───────────
-- it_cena_baza / it_suma_baza : added by the old path, renamed away later.
-- it_cena_suma                : only ever existed mid-path; dropped at the end.
-- discount_applied … promot_new : added by 03 — must not be here yet.
SELECT
  'D. item* promo/legacy columns absent' AS `check`,
  t.`name`  AS `table`,
  t.`col`   AS `column`,
  CASE
    WHEN tt.TABLE_NAME IS NULL   THEN 'n/a (table absent here)'
    WHEN col.COLUMN_NAME IS NULL THEN 'OK'
    ELSE 'FAIL — already present'
  END AS `result`
FROM (
            SELECT 'item'    AS `name`, 'it_cena_baza'     AS `col`
  UNION ALL SELECT 'item',              'it_suma_baza'
  UNION ALL SELECT 'item',              'it_cena_suma'
  UNION ALL SELECT 'item',              'discount_applied'
  UNION ALL SELECT 'item',              'it_cena_new'
  UNION ALL SELECT 'item',              'it_suma_new'
  UNION ALL SELECT 'item',              'item_br_new'
  UNION ALL SELECT 'item',              'promot_new'
  UNION ALL SELECT 'item_l',            'it_cena_baza'
  UNION ALL SELECT 'item_l',            'it_suma_baza'
  UNION ALL SELECT 'item_l',            'it_cena_suma'
  UNION ALL SELECT 'item_l',            'discount_applied'
  UNION ALL SELECT 'item_l',            'it_cena_new'
  UNION ALL SELECT 'item_l',            'it_suma_new'
  UNION ALL SELECT 'item_l',            'item_br_new'
  UNION ALL SELECT 'item_l',            'promot_new'
  UNION ALL SELECT 'item_no',           'it_cena_baza'
  UNION ALL SELECT 'item_no',           'it_suma_baza'
  UNION ALL SELECT 'item_no',           'it_cena_suma'
  UNION ALL SELECT 'item_no',           'discount_applied'
  UNION ALL SELECT 'item_no',           'it_cena_new'
  UNION ALL SELECT 'item_no',           'it_suma_new'
  UNION ALL SELECT 'item_no',           'item_br_new'
  UNION ALL SELECT 'item_no',           'promot_new'
) t
LEFT JOIN information_schema.TABLES tt
       ON tt.TABLE_SCHEMA = DATABASE()
      AND tt.TABLE_NAME   = t.`name`
LEFT JOIN information_schema.COLUMNS col
       ON col.TABLE_SCHEMA = DATABASE()
      AND col.TABLE_NAME   = t.`name`
      AND col.COLUMN_NAME  = t.`col`
ORDER BY t.`name`, t.`col`;


-- ── 5. porachki* promo columns must not exist yet (added by 04) ──────────────
SELECT
  'E. porachki* promo columns absent' AS `check`,
  t.`name`  AS `table`,
  t.`col`   AS `column`,
  CASE
    WHEN tt.TABLE_NAME IS NULL   THEN 'n/a (table absent here)'
    WHEN col.COLUMN_NAME IS NULL THEN 'OK'
    ELSE 'FAIL — already present'
  END AS `result`
FROM (
            SELECT 'porachki'    AS `name`, 'pordost_coupon_discount' AS `col`
  UNION ALL SELECT 'porachki',              'cendost_baza'
  UNION ALL SELECT 'porachki_l',            'pordost_coupon_discount'
  UNION ALL SELECT 'porachki_l',            'cendost_baza'
  UNION ALL SELECT 'porachki_l',            'promo_fixed_discount'
  UNION ALL SELECT 'porachki_no',           'pordost_coupon_discount'
  UNION ALL SELECT 'porachki_no',           'cendost_baza'
  UNION ALL SELECT 'porachki_no',           'promo_fixed_discount'
) t
LEFT JOIN information_schema.TABLES tt
       ON tt.TABLE_SCHEMA = DATABASE()
      AND tt.TABLE_NAME   = t.`name`
LEFT JOIN information_schema.COLUMNS col
       ON col.TABLE_SCHEMA = DATABASE()
      AND col.TABLE_NAME   = t.`name`
      AND col.COLUMN_NAME  = t.`col`
ORDER BY t.`name`, t.`col`;


-- ── 6. Engine sanity ────────────────────────────────────────────────────────
-- 07 adds real FKs, so InnoDB must be available.
SELECT
  'F. InnoDB available' AS `check`,
  ENGINE               AS `engine`,
  SUPPORT              AS `support`,
  IF(SUPPORT IN ('YES','DEFAULT'), 'OK', 'FAIL — 07 needs InnoDB for the FKs') AS `result`
FROM information_schema.ENGINES
WHERE ENGINE = 'InnoDB';


-- ── 7. catalog promo SKUs must not be seeded yet (added by 05) ───────────────
-- `catalog` has no UNIQUE KEY on cat_no, so 05 cannot protect itself — this query
-- is the only guard against a silent duplicate seed. Expected: Empty set.
-- Any row returned = FAIL, 05 has already run here.
--
-- REGIONAL DBs ONLY. Every check above reads information_schema and runs anywhere;
-- this last one reads `catalog` itself, so on imartap it raises ERROR 1146. Nothing
-- is written either way and it is deliberately the LAST statement, so just ignore
-- that error on imartap (or run the file with --force). Check A tells you which
-- target you are on. NEVER use --force on the migration files 01-09.
SELECT 'G. catalog promo SKUs absent' AS `check`,
       `cat_no`, `ime`, `vidimost`, `p_acti`
FROM `catalog`
WHERE `cat_no` IN ('5555555','6666666','7777777','8888888');
