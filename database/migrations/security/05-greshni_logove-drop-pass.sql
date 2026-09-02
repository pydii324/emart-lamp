-- =============================================================================
-- 05 — greshni_logove: drop the (now-empty) pass column
-- Target: imartap AND every regional DB.
-- Run:  mysql -D <db> < 05-greshni_logove-drop-pass.sql
--
-- Run this only weeks after 03 (see README "Ред на пускане" and the phase
-- table) — 03 empties the column, this removes it. Splitting the two gives a
-- window where a rollback of the code deploy still has somewhere to write if
-- something unexpected surfaces, without resurrecting the leak (an empty
-- column is not a leak).
--
-- Gol SQL, no guards. NOT idempotent — a second run fails with:
--   ERROR 1091 (42000): Can't DROP COLUMN `pass`; check that it exists
-- That is the signal that 05 has already run here.
-- =============================================================================

ALTER TABLE greshni_logove DROP COLUMN pass;
