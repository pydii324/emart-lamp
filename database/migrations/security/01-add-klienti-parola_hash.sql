-- =============================================================================
-- 01 — klienti: add parola_hash, a STAGING column for the CLI backfill script
-- Target: imartap AND every regional DB (klienti exists on both).
-- Run:  mysql -D <db> < 01-add-klienti-parola_hash.sql
--
-- klienti.parola — the pre-existing column — is the PERMANENT home for the
-- bcrypt hash going forward (reused, not replaced). parola_hash is only a
-- temporary handoff: the CLI backfill script (public_html/citte/cli/
-- backfill-parola-hash.php) writes a freshly-computed bcrypt hash here for
-- rows whose `parola` was still plaintext when it ran, because it can't
-- safely overwrite `parola` mid-scan out from under a concurrent login. No
-- live PHP read or write path (registration, Google/Facebook signup, login,
-- password change) ever names this column — they all write straight into
-- `parola`. 07-klienti-merge-and-drop-parola_hash.sql merges any leftover
-- values back into `parola` and drops this column once backfill is done.
--
-- Adds two nullable columns. This file is additive-safe on its own: it can
-- run days before any code deploy with zero behavior change.
--
--   parola_hash       bcrypt output ($2y$ from PHP, $2b$ from a future Bun/TS
--                      rewrite — both verify each other, see docs). NULL/empty
--                      means "nothing staged here" — irrelevant once a row's
--                      own `parola` is already bcrypt-shaped.
--   parola_hash_data   YmdHis of the last time parola_hash was set by the
--                      backfill script — same string format as
--                      klienti.data_reg / data_posl_logvane.
--
-- ascii/ascii_bin (not utf8mb3_unicode_ci like the neighboring columns): a
-- bcrypt hash is always `[./A-Za-z0-9$]` — ascii is the correct charset for
-- it, and ascii_bin keeps any future `WHERE parola_hash = '...'` comparison
-- byte-exact instead of accidentally case-insensitive. `parola` itself only
-- gets this treatment later, in 07, once every row is guaranteed bcrypt.
--
-- varchar(255), not char(60): $2y$/$2b$ bcrypt is exactly 60 characters, but
-- 255 leaves room if a future migration moves to argon2id without widening
-- the column again.
--
-- Gol SQL, no guards. NOT idempotent — on purpose. Running this twice on the
-- same DB fails on the first ALTER with:
--   ERROR 1060 (42S21): Duplicate column name 'parola_hash'
-- That is the signal that 01 has already run here — see 00-preflight check B.
-- =============================================================================

ALTER TABLE klienti
  ADD COLUMN parola_hash varchar(255)
    NULL DEFAULT NULL
    COMMENT 'bcrypt hash staging column, written only by the CLI backfill script. Not read by live app code — see file header.'
    AFTER parola;

ALTER TABLE klienti
  ADD COLUMN parola_hash_updated_at varchar(15) NULL DEFAULT NULL
    COMMENT 'YmdHis на последната смяна на parola_hash.'
    AFTER parola_hash;

-- Ако са пуснати миграциите в стария си вид, това е rollback към utf-8 на колоната
ALTER TABLE klienti
  MODIFY parola_hash VARCHAR(255)
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL;