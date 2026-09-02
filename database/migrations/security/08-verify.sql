-- =============================================================================
-- 08 — VERIFY (read-only, writes NOTHING)
-- Target: whichever DB you just migrated. Run after EVERY file in this set
-- that changes data or schema — not only at the very end.
-- Run: mysql -D <db> --table --force < 08-verify.sql
--
-- Checks A–C read information_schema only and run on ANY target without
-- erroring. Checks D onward read the tables themselves and are
-- target-specific, same layout as 00-preflight.sql — hence --force.
--
-- What this file CANNOT check: that a given parola_hash actually verifies
-- its plaintext counterpart, or a cross-DB comparison against imartap's
-- values. Both need PHP (password_verify) or a second connection — they live
-- in public_html/citte/cli/backfill-parola-hash.php --verify, not here.
-- =============================================================================

SELECT DATABASE() AS `db`, VERSION() AS `mysql_version`, NOW() AS `checked_at`;


-- ── A. schema present? ────────────────────────────────────────────────────
-- Just proves the staging columns exist (01 has run) — says nothing about
-- whether klienti is actually migrated, see check D for that.
SELECT
  'A. klienti staging columns' AS `check`,
  COLUMN_NAME AS `column`, COLUMN_TYPE AS `type`,
  CASE WHEN COLUMN_NAME IS NULL THEN 'FAIL — 01 has not run here' ELSE 'OK' END AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'klienti' AND COLUMN_NAME IN ('parola_hash','parola_hash_data')
ORDER BY COLUMN_NAME;


-- ── B. greshni_logove.pass — still there or already dropped? ───────────────
SELECT
  'B. greshni_logove.pass' AS `check`,
  COUNT(*) AS `column_present`,
  CASE WHEN COUNT(*) = 0 THEN 'DROPPED (05 has run)' ELSE 'PRESENT — should be empty until 05 runs' END AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'greshni_logove' AND COLUMN_NAME = 'pass';


-- ── C. zabpas.token_hash — schema present? ────────────────────── [regional] ─
SELECT
  'C. zabpas token_hash' AS `check`,
  COLUMN_NAME AS `column`, COLUMN_TYPE AS `type`,
  CASE WHEN COLUMN_NAME IS NULL THEN 'FAIL — 02 has not run here' ELSE 'OK' END AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'zabpas' AND COLUMN_NAME IN ('token_hash','izticha','izpolzvan')
ORDER BY COLUMN_NAME;


-- =============================================================================
-- Everything ABOVE reads information_schema only. Everything BELOW reads a
-- real table and is target-specific — expect ERROR 1146 on imartap for
-- D/E (no zabpas/tek there), tolerated by --force.
-- =============================================================================


-- ── D. klienti — anything still unmigrated? ─────────────────────────────────
-- "Migrated" means `parola` itself is bcrypt-shaped, full stop — regardless
-- of `parola_hash`. A row written by the new code has `parola` already
-- bcrypt and `parola_hash` empty by design (new writes never touch the
-- staging column), so a check keyed off parola_hash would wrongly flag it as
-- unmigrated forever. Gate for: running 07 statement 1 (merge) usefully, and
-- — critically — for the code deploy itself: vlizali.php has NO legacy
-- fallback, so any row still counted here cannot log in with its current
-- password at all once the new code is live. Also gates 07 statements 2/3.
SELECT
  'D. klienti still unmigrated' AS `check`,
  COUNT(*) AS `rows`,
  CASE WHEN COUNT(*) = 0 THEN 'OK — everything is bcrypt or empty' ELSE 'NOT DONE — run backfill and/or 07 statement 1 before deploying the new code' END AS `result`
FROM `klienti`
WHERE `parola` IS NOT NULL AND `parola` <> ''
  AND `parola` NOT LIKE '$2y$%' AND `parola` NOT LIKE '$2b$%';


-- ── E. klienti — parola_hash (staging column) shape ─────────────────────────
-- Every non-empty parola_hash must look like bcrypt and be exactly 60 chars.
-- Anything else means a corrupted backfill write — investigate before
-- trusting it. Meaningful only while the staging column still exists.
SELECT
  'E. parola_hash shape' AS `check`,
  COUNT(*) AS `hashed_rows`,
  COALESCE(SUM(`parola_hash` NOT LIKE '$2y$%' AND `parola_hash` NOT LIKE '$2b$%'), 0) AS `wrong_prefix`,
  COALESCE(SUM(LENGTH(`parola_hash`) <> 60), 0) AS `wrong_length`,
  CASE
    WHEN COUNT(*) = 0 THEN 'OK — nothing hashed yet'
    WHEN COALESCE(SUM(`parola_hash` NOT LIKE '$2y$%' AND `parola_hash` NOT LIKE '$2b$%'), 0) = 0
     AND COALESCE(SUM(LENGTH(`parola_hash`) <> 60), 0) = 0 THEN 'OK'
    ELSE 'FAIL — investigate'
  END AS `result`
FROM `klienti`
WHERE `parola_hash` IS NOT NULL AND `parola_hash` <> '';


-- ── F. greshni_logove — leak gone? ──────────────────────────────────────────
SELECT
  'F. greshni_logove leak' AS `check`,
  COUNT(*) AS `nonempty_pass_rows`,
  CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'STILL LEAKING — check 03 ran and the code deploy stopped writing pass' END AS `result`
FROM `greshni_logove`
WHERE `pass` IS NOT NULL AND `pass` <> '';
-- (No rows / ERROR 1146 after 05 has dropped the column — that is also OK.)


-- ── G. tek — leak gone? ──────────────────────────────────────── [regional] ─
SELECT
  'G. tek leak' AS `check`,
  COUNT(*) AS `password_rows`,
  CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'STILL LEAKING — check 04 ran and smenparoh.php stopped writing to tek' END AS `result`
FROM `tek`
WHERE `prm` IN ('sspp', 'nnpp1', 'nnpp2');


-- ── H. klienti — row count, for the cross-DB comparison against imartap ────
-- Run this on imartap too and diff by hand (or with
-- public_html/citte/cli/backfill-parola-hash.php --verify, which does it automatically
-- across every configured DB in one pass).
SELECT 'H. klienti row count' AS `check`, COUNT(*) AS `rows` FROM `klienti`;
