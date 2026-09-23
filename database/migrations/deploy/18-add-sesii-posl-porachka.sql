-- =============================================================================
-- 18 — sesii.posl_porachka: последната поръчка, завършена в тази сесия
-- Target: ВСЯКА регионална база (sesii е регионална).
-- Run: mysql -D <regional_db> --default-character-set=utf8mb4 < 18-add-sesii-posl-porachka.sql
--      (по веднъж за всеки регион)
--
-- WHY: страницата за потвърждение (/<3001>/<3006>, case_ptvd.php) взимаше
-- поръчката само по номера от cookie mart_podzav1. Номерата са поредни, така че
-- всеки с подменено cookie виждаше чужда поръчка — име, адрес, телефон, email.
-- podavam_za.php записва тук номера при финализиране, а case_ptvd.php показва
-- поръчката само ако съвпада със сесията на браузъра.
--
-- NULL = в тази сесия още няма завършена поръчка. Колоната е nullable без
-- DEFAULT, така че ALTER-ът е INSTANT на MySQL 8 — sesii не се копира.
-- =============================================================================

SET NAMES utf8mb4;

ALTER TABLE `sesii`
  ADD COLUMN `posl_porachka` INT NULL
    COMMENT 'porachki.porachki_id на последната поръчка от тази сесия — пази case_ptvd.php от IDOR';
