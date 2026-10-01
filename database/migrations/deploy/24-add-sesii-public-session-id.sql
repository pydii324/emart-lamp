-- =============================================================================
-- 24 — sesii.public_session_id: случайното id в биксвитките mart_bg / martbg
-- Target: ВСЯКА регионална база (sesii е регионална).
-- Run: mysql -D <regional_db> --default-character-set=utf8mb4 < 24-add-sesii-public-session-id.sql
--      (по веднъж за всеки регион)
--
-- ⚠ GATE — колегата може вече да я е пуснал с фикса на #19283 (main, 05cf353):
--
--     SHOW COLUMNS FROM sesii LIKE 'public_session_id';
--
--   1 ред = вече я има, ПРОПУСНИ файла.
--
-- WHY: mart_bg носеше sesii_id (AUTO_INCREMENT), така че всеки с подменено
-- cookie влизаше в чужда сесия, а през нея и в чуждата поръчка на
-- /potvardih-porachkata (QA #64). citte/utils/public-session-id.php пише тук
-- 32 случайни байта в hex и търси сесията по тях. Дефиницията е същата като в
-- Drizzle схемата (packages/db/src/regional-DB/schema.ts).
--
-- Старите цифрови cookie-та се приемат само ако promenliviprevodi 5190 (гост) /
-- 5191 (логнат) = '2'. Докато са '2', подменено цифрово cookie пак влиза в
-- чужда сесия (QA #64) — дръж ги '2' само за кратко след deploy. Редовете се
-- слагат с '1' (изключено): без тях sesii.php:443 печата „Undefined array key“
-- при display_errors, а това праща headers-ите и чупи всяко пренасочване.
-- INSERT IGNORE не пипа стойност, която колегата вече е сложил.
-- =============================================================================

SET NAMES utf8mb4;

ALTER TABLE `sesii`
  ADD COLUMN `public_session_id` CHAR(64) CHARACTER SET utf8mb3 COLLATE utf8mb3_unicode_ci NULL,
  ADD UNIQUE INDEX `uq_sesii_public_session_id` (`public_session_id`);

INSERT IGNORE INTO `promenliviprevodi` (`id`, `du`) VALUES (5190, '1'), (5191, '1');
