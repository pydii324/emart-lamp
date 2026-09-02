-- =============================================================================
-- 06 — zabpas: drop the legacy md5(time()) reset-token columns
-- Target: every regional DB only.
-- Run:  mysql -D <db> < 06-zabpas-drop-koda.sql
--
-- Run this only after promzabpas.php has stopped reading `koda`/`akt`
-- (feature flag id 5183 — see README) for at least as long as the longest
-- token lifetime that was ever issued against the old scheme (1 hour), plus
-- enough margin that no in-flight email link from the old scheme is still
-- being clicked.
--
-- Gol SQL, no guards. NOT idempotent — a second run fails with:
--   ERROR 1091 (42000): Can't DROP COLUMN `koda`; check that it exists
-- =============================================================================

ALTER TABLE zabpas DROP COLUMN koda;
ALTER TABLE zabpas DROP COLUMN akt;
