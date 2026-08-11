-- =============================================================================
-- 13 — cendost_baza (брутна цена за доставка, преди промо отстъпката)
-- Target: ALL DBs — регионални (porachki/porachki_l/porachki_no) И imartap
--         (porachki master). Пуска се срещу всяка база с porachki* таблица.
-- Run:  mysql -D <regional_db> < 13-add-cendost-baza.sql
--       mysql -D imartap       < 13-add-cendost-baza.sql
--
-- До момента се пазеха само нетната цена (`cendost`) и отстъпката
-- (`pordost_coupon_discount`); брутото беше изводимо единствено като сбор от
-- двете — и този сбор се чупеше, когато динамичният куриер презаписваше
-- `cendost` след финализация (podavam_za.php). Тази колона го снима явно.
--
-- Инвариант след миграцията:
--     porachki.cendost = MAX(0, cendost_baza − pordost_coupon_discount)
--
-- NULL DEFAULT NULL, за да е различима поръчка отпреди миграцията (нищо не е
-- записано → четящите падат на fallback `cendost + pordost_coupon_discount`)
-- от поръчка с легитимно бруто 0.00 (безплатна доставка над праг).
--
-- Гол SQL, без guards. НЕ е идемпотентно: при повторно пускане MySQL връща
-- `ERROR 1060 Duplicate column name 'cendost_baza'` и спира — това е сигналът.
-- =============================================================================

ALTER TABLE `porachki`    ADD COLUMN `cendost_baza` DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'gross delivery price before the shipping-promo discount';
ALTER TABLE `porachki_l`  ADD COLUMN `cendost_baza` DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'gross delivery price before the shipping-promo discount';
ALTER TABLE `porachki_no` ADD COLUMN `cendost_baza` DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'gross delivery price before the shipping-promo discount';
