-- =============================================================================
-- 02 — zabpas: hashed, expiring, single-use password-reset tokens
-- Target: every regional DB only. zabpas does not exist on imartap.
-- Run:  mysql -D <db> < 02-zabpas-secure-token.sql
--
-- Today's reset link carries md5(time()) — a hash of the CURRENT SECOND, i.e.
-- guessable within a few dozen attempts. This adds a proper token alongside
-- the old koda/akt columns so the code can dual-read during rollout:
--
--   token_hash   sha256 hex (64 chars) of a random 256-bit token. The raw
--                token goes in the emailed link and is NEVER stored — only
--                its hash, so a DB read alone can't produce a working link.
--   izticha      YmdHis expiry (replaces the "koda < now-3600" scan in
--                promzabpas.php with a direct comparison).
--   izpolzvan    2=used, 1=unused (project convention: 2=on/done, 1=off/not
--                yet — see kurieri.has_office for precedent). A used token
--                can never be replayed.
--
-- koda/akt are untouched here — the old md5(time()) path keeps working for
-- tokens already emailed and not yet clicked (they expire within an hour on
-- their own).
--
-- Gol SQL, no guards. NOT idempotent — on purpose. Running this twice fails on
-- the first ALTER with:
--   ERROR 1060 (42S21): Duplicate column name 'token_hash'
-- That is the signal that 02 has already run here — see 00-preflight check C.
-- =============================================================================

ALTER TABLE zabpas
  ADD COLUMN token_hash char(64)
    CHARACTER SET ascii COLLATE ascii_bin NULL DEFAULT NULL
    COMMENT 'sha256 hex на суровия reset токен. Суровият никога не се пази.'
    AFTER potreb_id;

ALTER TABLE zabpas
  ADD COLUMN izticha varchar(15) NULL DEFAULT NULL
    COMMENT 'YmdHis докога важи токенът.'
    AFTER token_hash;

ALTER TABLE zabpas
  ADD COLUMN izpolzvan tinyint NOT NULL DEFAULT 1
    COMMENT 'Токенът консумиран ли е? 2=да, 1=не.'
    AFTER izticha;

ALTER TABLE zabpas
  ADD INDEX token_hash (token_hash) USING BTREE;
