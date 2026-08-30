-- =============================================================================
-- 14 — kurieri: delivery-method flags + delivery-time range
-- Target: inmarta (единствената база с таблица `kurieri`).
-- Run:  mysql -D inmarta < 14-add-kurieri-delivery-options.sql
--
-- Разширява `kurieri` с:
--   - `kur_ime` от varchar(255) на varchar(2000) — някои куриерски имена/
--     описания вече не се събираха в 255 символа.
--   - `has_office` / `has_address` / `has_box` — булеви флагове (2=on, 1=off,
--     по конвенцията на таблицата) дали куриерът доставя до офис/адрес/
--     automat (box). Виждат се на case_dopl_no.php при избор на куриер.
--   - `min_delivery_time` / `max_delivery_time` — диапазон в дни за очаквана
--     доставка, показван на клиента.
--
-- Индексите `kur_vid` и `kur_no` са добавени тук за пълнота на дефиницията,
-- но на inmarta вече съществуват (MyISAM keys от по-стар schema) — ADD INDEX
-- пада с `ERROR 1061 Duplicate key name` на тази инстанция и това е
-- очаквано; пусни ги само ако целевата база още няма тези ключове.
--
-- Гол SQL, без guards. НЕ е идемпотентно: при повторно пускане MySQL връща
-- `ERROR 1060 Duplicate column name` (за колоните) — това е сигналът.
-- =============================================================================

ALTER TABLE kurieri MODIFY COLUMN kur_ime varchar(2000) CHARACTER SET utf8mb3 COLLATE utf8mb3_unicode_ci NULL DEFAULT NULL AFTER kurieri_id;
ALTER TABLE kurieri ADD COLUMN has_office tinyint NOT NULL DEFAULT 2 COMMENT 'Доставя ли куриера до офис? 2=on, 1=off' AFTER kur_vid;
ALTER TABLE kurieri ADD COLUMN has_address tinyint NOT NULL DEFAULT 2 COMMENT 'Доставя ли куриера до адрес? 2=on, 1=off' AFTER has_office;
ALTER TABLE kurieri ADD COLUMN has_box tinyint NOT NULL DEFAULT 1 COMMENT 'Доставя ли куриера до автомат?  2=on, 1=off' AFTER has_address;
ALTER TABLE kurieri ADD COLUMN min_delivery_time tinyint UNSIGNED NOT NULL DEFAULT 2 AFTER has_box;
ALTER TABLE kurieri ADD COLUMN max_delivery_time tinyint UNSIGNED NOT NULL DEFAULT 5 AFTER min_delivery_time;
ALTER TABLE kurieri ADD INDEX kur_vid(kur_vid) USING BTREE;
ALTER TABLE kurieri ADD INDEX kur_no(kur_no) USING BTREE;
