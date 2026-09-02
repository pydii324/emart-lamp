-- =============================================================================
-- 07 — klienti: merge parola_hash into parola, then retire parola_hash
-- Target: imartap AND every regional DB.
-- Run:  mysql -D <db> < 07-klienti-merge-and-drop-parola_hash.sql
--
-- klienti.parola is the PERMANENT home for the bcrypt hash — reused, not
-- replaced. klienti.parola_hash was only ever a staging column, written by
-- the CLI backfill script for rows that were still plaintext when it ran.
-- Live code (novreg.php, vlizali.php, vlizalig.php, vlizalif.php,
-- smenparo.php, smenparoh.php) has written bcrypt directly into `parola`
-- since the code deploy — the only rows this file still needs to touch are
-- ones backfilled but never logged in or changed their password since.
--
-- Three statements, two different risk profiles:
--
--   1) UPDATE ... SET parola = parola_hash   — safe, idempotent, NOT gated.
--      Can run any time after backfill (--source + --mirror) has completed —
--      it only ever converts a row from "plaintext, needs the legacy
--      fallback" to "bcrypt, fast path", never the reverse (see the WHERE
--      guard below). Does NOT require feature flag 5182 to be off first.
--      Running it right after backfill, rather than deferring it to the end
--      with statements 2/3, is recommended.
--
--   2) ALTER ... MODIFY parola ... ascii/ascii_bin   — GATED, semi-reversible
--      (a further ALTER can widen/re-collate back, but see the warning
--      below about data loss if run too early).
--
--   3) ALTER ... DROP COLUMN parola_hash*   — GATED, IRREVERSIBLE.
--
-- Run statements 2 and 3 only:
--   - after 08-verify.sql's check D reports 0 on every target (every
--     klienti.parola is empty or already bcrypt-shaped — same condition
--     whether a row got there via statement 1, a lazy upgrade at login, or a
--     fresh write since the code deploy), AND
--   - at least 2–4 weeks after feature flag id 5182 was switched to 1
--     (legacy fallback off) and stayed there without incident.
-- Take an offline `mysqldump` of `klienti` on every target BEFORE running
-- statements 2/3, kept somewhere outside this server. There is no rollback
-- for a dropped column, and statement 2 is destructive if run too early: it
-- converts `parola` to the `ascii` charset, which corrupts or errors on any
-- row that is STILL real plaintext (Cyrillic passwords are common here) —
-- that is exactly what check D = 0 guarantees is no longer the case.
--
-- If you are running 1 and 2/3 in the same sitting, that is a sign this is
-- being rushed — re-read the phase table in README.md first.
--
-- Gol SQL, no guards. Statement 1 is idempotent (0 rows matched on a second
-- run once everything is merged). Statements 2/3 are NOT — a second run of
-- statement 3 fails with:
--   ERROR 1091 (42000): Can't DROP COLUMN `parola_hash`; check that it exists
-- =============================================================================

-- 1) Merge: copy the staged backfill hash into `parola` for any row that
--    hasn't already been converted by a fresher write. The guard against
--    clobbering is `parola` not already being bcrypt-shaped — a row whose
--    user changed their password (or lazy-upgraded at login) AFTER being
--    backfilled already has the CORRECT, newer hash in `parola`; blindly
--    copying the stale parola_hash over it would silently revert them to an
--    old password hash and lock them out. `parola IS NULL` is handled
--    explicitly, not folded into the NOT LIKE checks — MySQL's three-valued
--    logic makes `NULL NOT LIKE 'x'` evaluate to NULL (excluded from a
--    WHERE), not TRUE, so a NULL `parola` would otherwise be silently
--    skipped even though it clearly needs the merge.
UPDATE klienti
SET parola = parola_hash
WHERE parola_hash IS NOT NULL AND parola_hash <> ''
  AND (parola IS NULL OR (parola NOT LIKE '$2y$%' AND parola NOT LIKE '$2b$%'));

-- ── GATE — do not run statements 2/3 until 08-verify.sql check D = 0 on
--    every target AND flag 5182 has been off for 2–4 weeks. See header. ────

-- 2) Now that every non-empty `parola` is guaranteed pure-ASCII bcrypt,
--    widen and re-collate it the same way parola_hash always was —
--    ascii_bin so any future `WHERE parola = '...'` stays byte-exact instead
--    of accidentally case-insensitive (bcrypt is case-sensitive), and
--    varchar(255) (bcrypt is 60 chars) leaves room for argon2id later
--    without a further migration.
ALTER TABLE klienti
  MODIFY parola varchar(255) NULL DEFAULT NULL
    COMMENT 'bcrypt hash ($2y$/$2b$). Formerly urlencode(plaintext) — fully migrated once this ALTER ran.';

-- 3) Retire the staging column — nothing reads it anymore.
ALTER TABLE klienti /* DROP COLUMN parola_hash_updated_at, */ DROP COLUMN parola_hash;

-- Ако са пуснати миграциите в стария си вид, това е rollback към utf-8 на колоната
ALTER TABLE klienti
  MODIFY parola VARCHAR(255)
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL;