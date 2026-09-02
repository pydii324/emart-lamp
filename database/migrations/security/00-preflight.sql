-- =============================================================================
-- 00 — PRE-FLIGHT (read-only, writes NOTHING)
-- Target: EVERY DB you are about to touch — imartap AND every regional DB.
-- Run: mysql -D <db> --table --force < 00-preflight.sql
--
-- The rest of this set is plain, unguarded SQL: the first bad statement aborts
-- the file and leaves the earlier statements applied. This file proves up-front
-- what baseline the target is on, so that never happens by surprise.
--
-- EXPECTED STARTING STATE (what this set migrates FROM):
--   klienti.parola          holds urlencode(plaintext) — no hashing at all
--   klienti.parola_hash     does not exist yet
--   greshni_logove.pass     holds the plaintext password typed on a failed login
--   zabpas.koda             holds md5(time())-derived reset tokens (guessable)
--   tek                     may hold plaintext passwords under prm IN
--                           ('sspp','nnpp1','nnpp2') — the "repopulate the form
--                           after an error" mechanism
--
-- WHICH TABLES LIVE WHERE (confirmed against a live instance, not assumed):
--   imartap:   klienti, greshni_logove              (NOT zabpas, tek, promenliviprevodi)
--   regional:  klienti, greshni_logove, zabpas, tek, promenliviprevodi
--
-- Checks A–C read information_schema only and run on ANY target without
-- erroring: a table or column that does not exist here is simply a missing
-- row, never an error. Checks D onward read the tables themselves and are
-- target-specific as marked — a check against a table absent on this target
-- raises ERROR 1146, which is why this file wants --force. Nothing here
-- writes. NEVER use --force on files 01–07.
-- =============================================================================

SELECT DATABASE() AS `db`, VERSION() AS `mysql_version`, NOW() AS `checked_at`;


-- ── A. Which target am I on? ─────────────────────────────────────────────────
SELECT
  'A. relevant tables present' AS `check`,
  TABLE_NAME                   AS `table`,
  TABLE_ROWS                   AS `approx_rows`
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('klienti','greshni_logove','tek','zabpas','promenliviprevodi')
ORDER BY TABLE_NAME;


-- ── B. klienti.parola_hash — the columns file 01 adds ────────────────────────
-- A row here means 01 has already run on this target — skip it.
-- Empty result set is the OK case (01 has not run yet); there is no row to
-- print for "not yet migrated", read absence as the good outcome.
SELECT
  'B. parola_hash column' AS `check`,
  COLUMN_NAME             AS `column`,
  COLUMN_TYPE             AS `type`,
  'ALREADY DONE — 01 has run here, skip it' AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'klienti' AND COLUMN_NAME IN ('parola_hash','parola_hash_data')
ORDER BY COLUMN_NAME;


-- ── C. zabpas.token_hash — the columns file 02 adds ─────────────────────────
-- Same logic as B, for the reset-token columns. Empty on imartap by
-- definition (imartap has no zabpas table at all) — that is not a FAIL, 02
-- simply does not target imartap.
SELECT
  'C. zabpas token_hash column' AS `check`,
  COLUMN_NAME                   AS `column`,
  COLUMN_TYPE                   AS `type`,
  'ALREADY DONE — 02 has run here, skip it' AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'zabpas' AND COLUMN_NAME IN ('token_hash','izticha','izpolzvan')
ORDER BY COLUMN_NAME;


-- =============================================================================
-- Everything ABOVE reads information_schema only → runs on ANY target, no
-- errors. Everything BELOW reads a real table and is target-specific as
-- marked: on imartap, D/H/I raise ERROR 1146 (no zabpas/tek/promenliviprevodi
-- there) — expected, tolerated by --force. Nothing here writes either way.
-- =============================================================================


-- ── D. promenliviprevodi feature-flag id 5183 — free? ───────────── [regional] ─
-- Not created by any migration in this repo (promenliviprevodi is
-- seeded/managed outside the SQL migration system — see README.md). Only
-- 5183 (legacy md5 reset-token acceptance window) is still part of this
-- design — the login/password-change legacy fallback that id 5182 used to
-- gate was removed from the live code entirely, so 5182 was dropped from
-- this migration set (nothing reads it).
SELECT
  'D. id 5183 already used?' AS `check`,
  `id`, `du` AS `current_value`,
  'FAIL — id already in use for something else, pick a free id and update the plan/code' AS `result`
FROM `promenliviprevodi`
WHERE `id` = 5183;
-- Empty result set = free, proceed with 5183 as documented.


-- ── E. backfill volume — how many klienti.parola rows need hashing ──────────
SELECT
  'E. klienti backfill volume' AS `check`,
  COUNT(*)                     AS `rows_with_plaintext_parola`
FROM `klienti`
WHERE `parola` IS NOT NULL AND `parola` <> '';


-- ── F. any value in parola that already looks like bcrypt? ──────────────────
-- Should be 0 — this set has never run here yet, so nothing should look hashed.
SELECT
  'F. parola already bcrypt-shaped?' AS `check`,
  COUNT(*)                            AS `rows`,
  CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FAIL — investigate before continuing' END AS `result`
FROM `klienti`
WHERE `parola` LIKE '$2y$%' OR `parola` LIKE '$2b$%';


-- ── G. greshni_logove — plaintext-password leak volume ───────────────────────
SELECT
  'G. greshni_logove.pass non-empty' AS `check`,
  COUNT(*)                            AS `rows`
FROM `greshni_logove`
WHERE `pass` IS NOT NULL AND `pass` <> '';


-- ── H. tek — plaintext-password leak volume ─────────────────────── [regional] ─
SELECT
  'H. tek plaintext-password rows' AS `check`,
  `prm`, COUNT(*) AS `rows`
FROM `tek`
WHERE `prm` IN ('sspp','nnpp1','nnpp2')
GROUP BY `prm`;


-- ── I. klienti row count — reference for the cross-DB check in 08-verify ────
SELECT 'I. klienti row count' AS `check`, COUNT(*) AS `rows` FROM `klienti`;
