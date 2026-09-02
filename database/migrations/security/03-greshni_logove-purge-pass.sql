-- =============================================================================
-- 03 — greshni_logove: purge the plaintext-password leak
-- Target: imartap AND every regional DB.
-- Run:  mysql -D <db> < 03-greshni_logove-purge-pass.sql
--
-- ⚠ ORDER MATTERS: run this only AFTER the code deploy that stops writing
-- `pass` (citte/vlizali.php no longer sets `pass = '<typed password>'` on a
-- failed login, and writes the failure reason into the existing `komentar`
-- column instead). Purge before that deploy and the column just refills.
--
-- The UPDATE is the ONLY idempotent statement in this whole set — a second
-- run matches 0 rows and succeeds silently, because it targets `pass <> ''`
-- and the first run already made every row `''`. That is deliberate: this
-- statement may need re-running if 03 is applied before the code deploy by
-- mistake, without turning into a hard failure.
--
-- The index supports a future server-side login rate limit
-- (SELECT COUNT(*) FROM greshni_logove WHERE ip = ? AND data > <15 min ago>)
-- — out of scope for this set, added here because this is where the table
-- gets touched anyway.
--
-- Gol SQL, no guards for the ADD INDEX. Running that part twice fails with:
--   ERROR 1061 (42000): Duplicate key name 'ip_data'
-- =============================================================================

UPDATE greshni_logove SET pass = '' WHERE pass IS NOT NULL AND pass <> '';

ALTER TABLE greshni_logove ADD INDEX ip_data (ip, data) USING BTREE;
