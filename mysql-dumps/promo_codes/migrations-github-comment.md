## `new/` — Fresh install (no existing tables)

| # | Файл | Target | Какво прави |
|---|---|---|---|
| 01 | create-promo_codes | imartap | Финална schema — subtype + shipping_percent вградени |
| 02 | pre-flight-checks | imartap | Диагностика преди миграция |
| 03 | migrate-loyality_points | imartap | |
| 04 | migrate-obshti_kodove | imartap | |
| 05 | verify-imartap | imartap | Post-миграция проверки |
| 06 | add-item-columns | all DBs | discount_applied + baza колони на item\* |
| 07 | add-porachki-columns | all DBs | pordost_coupon_discount + promo_fixed_discount на porachki\* |
| 08 | catalog-promo-skus | regional | SKU seed за Микроинвест |
| 09 | create-cart_promo_codes | regional | Без FK, включва discount_value + subtype |
| 10 | create-order_promo_codes | regional | Без FK |
| 11 | verify-per-db | all DBs | Финална проверка |

> **imartap** = инстанцията с promo_codes каталога  
> **regional** = per-site инстанцията с количката (item_l/no, porachki_l/no)  
> **all DBs** = и двете — пускай срещу всяка база през batch tool-а

---

### `new/01-create-promo_codes.sql`

```sql
USE imartap;

CREATE TABLE IF NOT EXISTS `promo_codes` (
  `id`              INT           NOT NULL AUTO_INCREMENT,
  `code`            VARCHAR(50)   NOT NULL,
  `type`            ENUM('percent','fixed','shipping','shipping_percent') NOT NULL DEFAULT 'percent',
  `subtype`         ENUM('voucher','coupon') NULL DEFAULT NULL COMMENT 'fixed only: NULL/voucher → SKU 5555555, coupon → SKU 7777777',
  `discount_value`  DECIMAL(10,2) NOT NULL,
  `min_subtotal`    DECIMAL(10,2) NOT NULL DEFAULT 0,
  `shipping_cap`    DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'shipping/shipping_percent: max discount лв.; NULL = uncapped',
  `max_uses`        INT           NOT NULL DEFAULT 0 COMMENT '0 = unlimited',
  `times_used`      INT           NOT NULL DEFAULT 0,
  `active`          BOOLEAN       NOT NULL DEFAULT TRUE,
  `stack_group`     TINYINT       NULL DEFAULT NULL COMMENT 'NULL = stacks freely; same number = only 1 from group',
  `expiration_date` VARCHAR(14)   NULL DEFAULT NULL COMMENT 'YYYYMMDDHHmmss; NULL = no expiry',
  `created_at`      VARCHAR(14)   NOT NULL,
  `used_at`         VARCHAR(14)   NULL DEFAULT NULL,
  `source`          ENUM('the-marketer','manual','bulk-import') NOT NULL DEFAULT 'manual',
  `note`            VARCHAR(255)  NULL DEFAULT NULL,
  `site`            VARCHAR(10)   NULL DEFAULT NULL COMMENT 'bg/ro/gr/all',
  `created_by`      VARCHAR(255)  NULL DEFAULT NULL,

  PRIMARY KEY (`id`),
  UNIQUE KEY `code` (`code`),
  KEY `idx_active_exp` (`active`, `expiration_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### `new/02-pre-flight-checks.sql`

```sql
USE imartap;

SELECT 'loyality_points' AS tbl, MAX(LENGTH(kod)) AS max_len, COUNT(*) AS total FROM loyality_points
UNION ALL
SELECT 'obshti_kodove',          MAX(LENGTH(kod)),             COUNT(*) FROM obshti_kodove;

SELECT 'loyality NULL/bad tip' AS lbl, COUNT(*) AS cnt FROM loyality_points WHERE tip IS NULL OR tip NOT IN (0,1,2)
UNION ALL
SELECT 'obshti NULL/bad tip',   COUNT(*) FROM obshti_kodove WHERE tip IS NULL OR tip NOT IN (0,1,2);

SELECT l.kod AS colliding_code, l.id AS loyality_id, o.id AS obshti_id
FROM loyality_points l
JOIN obshti_kodove o ON l.kod = o.kod;

SELECT 'loyality empty kod' AS lbl, COUNT(*) AS cnt FROM loyality_points WHERE kod IS NULL OR kod = ''
UNION ALL
SELECT 'obshti empty kod',   COUNT(*) FROM obshti_kodove WHERE kod IS NULL OR kod = '';

SELECT 'loyality_points'      AS tbl, COUNT(*) AS total FROM loyality_points
UNION ALL
SELECT 'obshti_kodove',               COUNT(*) FROM obshti_kodove
UNION ALL
SELECT 'promo_codes (before)',         COUNT(*) FROM promo_codes;
```

### `new/03-migrate-loyality_points.sql`

```sql
USE imartap;

INSERT IGNORE INTO promo_codes
  (code, type, discount_value,
   max_uses, active,
   expiration_date, created_at, used_at,
   source, note, site, created_by)
SELECT
   kod,
   CASE tip WHEN 0 THEN 'fixed' WHEN 1 THEN 'percent' WHEN 2 THEN 'shipping' ELSE 'percent' END,
   CAST(value AS DECIMAL(10,2)),
   1,
   IF(izpolzvan = '1', 0, 1),
   data_validen,
   data_sazdaden,
   data_izpolzvan,
   'the-marketer',
   komentar,
   sait,
   COALESCE(NULLIF(ot_kade, ''), 'the-marketer')
FROM loyality_points
WHERE kod IS NOT NULL AND kod <> ''
  AND tip IN (0, 1, 2);
```

### `new/04-migrate-obshti_kodove.sql`

```sql
USE imartap;

INSERT IGNORE INTO promo_codes
  (code, type, discount_value,
   max_uses, active,
   expiration_date, created_at, used_at,
   source, note, site, created_by)
SELECT
   kod,
   CASE tip WHEN 0 THEN 'fixed' WHEN 1 THEN 'percent' WHEN 2 THEN 'shipping' ELSE 'percent' END,
   CAST(value AS DECIMAL(10,2)),
   0,
   IF(data_validen IS NULL OR data_validen > DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'), 1, 0),
   data_validen,
   data_sazdaden,
   NULL,
   'manual',
   komentar,
   sait,
   NULLIF(ot_kade, '')
FROM obshti_kodove
WHERE kod IS NOT NULL AND kod <> ''
  AND tip IN (0, 1, 2);
```

### `new/05-verify-imartap.sql`

```sql
USE imartap;

SELECT
   (SELECT COUNT(*) FROM loyality_points)                         AS loyality_total,
   (SELECT COUNT(*) FROM obshti_kodove)                           AS obshti_total,
   (SELECT COUNT(*) FROM promo_codes)                             AS promo_total,
   (SELECT COUNT(*) FROM promo_codes WHERE source='the-marketer') AS from_marketer,
   (SELECT COUNT(*) FROM promo_codes WHERE source='manual')       AS from_manual;

SELECT 'missing from loyality' AS lbl, l.id, l.kod
FROM loyality_points l
LEFT JOIN promo_codes p ON p.code = l.kod
WHERE p.id IS NULL AND l.kod IS NOT NULL AND l.kod <> '' AND l.tip IN (0,1,2)
UNION ALL
SELECT 'missing from obshti', o.id, o.kod
FROM obshti_kodove o
LEFT JOIN promo_codes p ON p.code = o.kod
WHERE p.id IS NULL AND o.kod IS NOT NULL AND o.kod <> '' AND o.tip IN (0,1,2);

SELECT source, type, COUNT(*) AS cnt
FROM promo_codes
GROUP BY source, type
ORDER BY source, type;

SELECT COLUMN_NAME, COLUMN_TYPE
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'imartap' AND TABLE_NAME = 'promo_codes'
  AND COLUMN_NAME IN ('type','subtype','shipping_cap','times_used')
ORDER BY COLUMN_NAME;
```

### `new/06-add-item-columns.sql`

```sql
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l' AND COLUMN_NAME = 'discount_applied'),
  'ALTER TABLE `item_l` ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l' AND COLUMN_NAME = 'it_suma_baza'),
  'ALTER TABLE `item_l` ADD COLUMN `it_cena_baza` FLOAT NULL DEFAULT NULL, ADD COLUMN `it_suma_baza` FLOAT NULL DEFAULT NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l' AND COLUMN_NAME = 'it_suma_baza'),
  'UPDATE `item_l` SET `it_suma_baza` = `it_suma` + `discount_applied`, `it_cena_baza` = (`it_suma` + `discount_applied`) / GREATEST(`item_br`, 1) WHERE `it_suma_baza` IS NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no' AND COLUMN_NAME = 'discount_applied'),
  'ALTER TABLE `item_no` ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no' AND COLUMN_NAME = 'it_suma_baza'),
  'ALTER TABLE `item_no` ADD COLUMN `it_cena_baza` FLOAT NULL DEFAULT NULL, ADD COLUMN `it_suma_baza` FLOAT NULL DEFAULT NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no' AND COLUMN_NAME = 'it_suma_baza'),
  'UPDATE `item_no` SET `it_suma_baza` = `it_suma` + `discount_applied`, `it_cena_baza` = (`it_suma` + `discount_applied`) / GREATEST(`item_br`, 1) WHERE `it_suma_baza` IS NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item' AND COLUMN_NAME = 'discount_applied'),
  'ALTER TABLE `item` ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item' AND COLUMN_NAME = 'it_suma_baza'),
  'ALTER TABLE `item` ADD COLUMN `it_cena_baza` FLOAT NULL DEFAULT NULL, ADD COLUMN `it_suma_baza` FLOAT NULL DEFAULT NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item' AND COLUMN_NAME = 'it_suma_baza'),
  'UPDATE `item` SET `it_suma_baza` = `it_suma` + `discount_applied`, `it_cena_baza` = (`it_suma` + `discount_applied`) / GREATEST(`item_br`, 1) WHERE `it_suma_baza` IS NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
```

### `new/07-add-porachki-columns.sql`

```sql
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki' AND COLUMN_NAME = 'pordost_coupon_discount'),
  'ALTER TABLE `porachki` ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_l' AND COLUMN_NAME = 'pordost_coupon_discount'),
  'ALTER TABLE `porachki_l` ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_l' AND COLUMN_NAME = 'promo_fixed_discount'),
  'ALTER TABLE `porachki_l` ADD COLUMN `promo_fixed_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_no' AND COLUMN_NAME = 'pordost_coupon_discount'),
  'ALTER TABLE `porachki_no` ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_no' AND COLUMN_NAME = 'promo_fixed_discount'),
  'ALTER TABLE `porachki_no` ADD COLUMN `promo_fixed_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
```

### `new/08-catalog-promo-skus.sql`

```sql
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'catalog'),
  'INSERT IGNORE INTO `catalog` (`cat_no`, `ime`, `miarka`, `cena`, `nnindex`) VALUES
     (''5555555'', ''Промо ваучер/купон'',       ''бр.'', 0.00, ''promo-5555555''),
     (''6666666'', ''Промо безплатна доставка'', ''бр.'', 0.00, ''promo-6666666''),
     (''7777777'', ''Промо купон'',              ''бр.'', 0.00, ''promo-7777777''),
     (''8888888'', ''Промо процентна отстъпка'', ''бр.'', 0.00, ''promo-8888888'')',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
```

### `new/09-create-cart_promo_codes.sql`

```sql
CREATE TABLE IF NOT EXISTS `cart_promo_codes` (
  `id`               INT           NOT NULL AUTO_INCREMENT,
  `cart_id`          INT           NOT NULL,
  `cart_type`        ENUM('l','no') NOT NULL COMMENT 'l = porachki_l, no = porachki_no',
  `promo_code_id`    INT           NOT NULL COMMENT 'imartap.promo_codes.id — no cross-instance FK',
  `code`             VARCHAR(50)   NOT NULL,
  `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `discount_value`   DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT 'snapshot at apply-time; avoids cross-instance read at recalc',
  `type`             ENUM('percent','fixed','shipping','shipping_percent') NOT NULL,
  `subtype`          ENUM('voucher','coupon') NULL DEFAULT NULL,
  `shipping_cap`     DECIMAL(10,2) NULL DEFAULT NULL,
  `created_at`       VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_cart_promo` (`cart_id`, `cart_type`, `promo_code_id`),
  KEY `idx_promo_code` (`promo_code_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### `new/10-create-order_promo_codes.sql`

```sql
CREATE TABLE IF NOT EXISTS `order_promo_codes` (
  `id`                 INT           NOT NULL AUTO_INCREMENT,
  `order_id`           INT           NOT NULL COMMENT 'porachki.porachki_id',
  `promo_code_id`      INT           NOT NULL COMMENT 'imartap.promo_codes.id — no cross-instance FK',
  `klienti_id`         INT           NOT NULL DEFAULT 0 COMMENT '0 = guest',
  `discount_applied`   DECIMAL(10,2) NOT NULL,
  `used_by_employeeId` INT           NULL DEFAULT NULL COMMENT 'backoffice app; storefront leaves NULL',
  `created_at`         VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_order_promo` (`order_id`, `promo_code_id`),
  KEY `idx_klienti` (`klienti_id`, `promo_code_id`),
  KEY `idx_promo_code` (`promo_code_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### `new/11-verify-per-db.sql`

```sql
SELECT TABLE_NAME, COLUMN_NAME, COLUMN_TYPE
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND (
    (TABLE_NAME IN ('item','item_l','item_no') AND COLUMN_NAME IN ('discount_applied','it_cena_baza','it_suma_baza'))
    OR
    (TABLE_NAME IN ('porachki','porachki_l','porachki_no') AND COLUMN_NAME IN ('pordost_coupon_discount','promo_fixed_discount'))
  )
ORDER BY TABLE_NAME, COLUMN_NAME;

SELECT
  DATABASE()                                        AS db,
  SUM(TABLE_NAME = 'promo_codes')                   AS has_promo_codes,
  SUM(TABLE_NAME = 'cart_promo_codes')              AS has_cart_promo_codes,
  SUM(TABLE_NAME = 'order_promo_codes')             AS has_order_promo_codes
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('promo_codes','cart_promo_codes','order_promo_codes');

SELECT COLUMN_NAME, COLUMN_TYPE
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'cart_promo_codes'
  AND COLUMN_NAME IN ('discount_value','subtype','type','shipping_cap')
ORDER BY COLUMN_NAME;
```

---

### `old/01-create-promo_codes.sql`

```sql
USE imartap;

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS `promo_codes`;

CREATE TABLE `promo_codes` (
  `id`                INT           NOT NULL AUTO_INCREMENT,
  `code`              VARCHAR(50)   NOT NULL,
  `type`              ENUM('percent','fixed','shipping') NOT NULL DEFAULT 'percent',

  `discount_value`    DECIMAL(10,2) NOT NULL,
  `voucher_remainer`  DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'само за fixed — бюджет, намалява при употреба',

  `min_subtotal`      DECIMAL(10,2) NOT NULL DEFAULT 0,
  `shipping_cap`      DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'само за shipping (NULL = без cap)',
  `max_uses`          INT           NOT NULL DEFAULT 0 COMMENT '0 = безлимит',
  `times_used`        INT           NOT NULL DEFAULT 0 COMMENT 'брояч на употреби; ++ при markUsed()',

  `active`            BOOLEAN       NOT NULL DEFAULT TRUE,
  `stack_group`       TINYINT       NULL DEFAULT NULL COMMENT 'NULL = комбинира се с всичко',

  `expiration_date`   VARCHAR(14)   NULL DEFAULT NULL,
  `created_at`        VARCHAR(14)   NOT NULL,
  `used_at`           VARCHAR(14)   NULL DEFAULT NULL COMMENT 'last-used; update-ва се при markUsed()',

  `source`            ENUM('the-marketer','manual','bulk-import') NOT NULL DEFAULT 'manual',
  `note`              VARCHAR(255)  NULL DEFAULT NULL COMMENT 'бивш komentar',
  `site`              VARCHAR(10)   NULL DEFAULT NULL COMMENT 'бивш sait — bg/ro/gr/all',
  `created_by`        VARCHAR(255)  NULL DEFAULT NULL COMMENT 'бивш ot_kade — free-form audit',

  PRIMARY KEY (`id`),
  UNIQUE KEY `code` (`code`),
  KEY `idx_active_exp` (`active`, `expiration_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
```

### `old/02-create-cart_promo_codes.sql`

```sql
USE imartap;

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS `cart_promo_codes`;

CREATE TABLE `cart_promo_codes` (
  `id`               INT           NOT NULL AUTO_INCREMENT,
  `cart_id`          INT           NOT NULL,
  `cart_type`        ENUM('l','no') NOT NULL COMMENT "'l' = porachki_l (logged-in), 'no' = porachki_no (guest)",
  `promo_code_id`    INT           NOT NULL,
  `code`             VARCHAR(50)   NOT NULL,
  `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '0 за type=shipping; реална deduction за percent/fixed',
  `type`             ENUM('percent','fixed','shipping') NOT NULL,
  `shipping_cap`     DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'само за type=shipping',
  `created_at`       VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_cart_promo` (`cart_id`, `cart_type`, `promo_code_id`),
  CONSTRAINT `fk_cpc_promo` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
```

### `old/03-create-order_promo_codes.sql`

```sql
USE imartap;

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS `order_promo_codes`;

CREATE TABLE `order_promo_codes` (
  `id`               INT           NOT NULL AUTO_INCREMENT,
  `order_id`         INT           NOT NULL COMMENT 'porachki.porachki_id',
  `promo_code_id`    INT           NOT NULL,
  `klienti_id`       INT           NOT NULL DEFAULT 0 COMMENT '0 = гост',
  `discount_applied` DECIMAL(10,2) NOT NULL,
  `created_at`       VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_order_promo` (`order_id`, `promo_code_id`),
  KEY `idx_klienti` (`klienti_id`, `promo_code_id`),
  CONSTRAINT `fk_opc_promo` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
```

### `old/04-pre-flight-checks.sql`

```sql
USE imartap;

SELECT 'loyality_points' AS tbl, MAX(LENGTH(kod)) AS max_len, COUNT(*) AS total FROM loyality_points
UNION ALL
SELECT 'obshti_kodove'    AS tbl, MAX(LENGTH(kod)) AS max_len, COUNT(*) AS total FROM obshti_kodove;

SELECT 'loyality NULL/bad tip' AS lbl, COUNT(*) AS cnt FROM loyality_points WHERE tip IS NULL OR tip NOT IN (0,1,2)
UNION ALL
SELECT 'obshti NULL/bad tip'    AS lbl, COUNT(*) AS cnt FROM obshti_kodove   WHERE tip IS NULL OR tip NOT IN (0,1,2);

SELECT l.kod AS colliding_code,
       l.id  AS loyality_id,
       o.id  AS obshti_id
FROM loyality_points l
JOIN obshti_kodove o ON l.kod = o.kod;

SELECT 'loyality empty kod' AS lbl, COUNT(*) AS cnt FROM loyality_points WHERE kod IS NULL OR kod = ''
UNION ALL
SELECT 'obshti empty kod'    AS lbl, COUNT(*) AS cnt FROM obshti_kodove   WHERE kod IS NULL OR kod = '';

SELECT 'loyality bad date' AS lbl, COUNT(*) AS cnt FROM loyality_points
  WHERE data_validen IS NOT NULL
    AND (LENGTH(data_validen) <> 14 OR data_validen NOT REGEXP '^[0-9]{14}$')
UNION ALL
SELECT 'obshti bad date'    AS lbl, COUNT(*) AS cnt FROM obshti_kodove
  WHERE data_validen IS NOT NULL
    AND (LENGTH(data_validen) <> 14 OR data_validen NOT REGEXP '^[0-9]{14}$');

SELECT 'loyality_points'      AS tbl, COUNT(*) AS total FROM loyality_points
UNION ALL
SELECT 'obshti_kodove'        AS tbl, COUNT(*) AS total FROM obshti_kodove
UNION ALL
SELECT 'promo_codes (before)' AS tbl, COUNT(*) AS total FROM promo_codes;
```

### `old/05-migrate-loyality_points.sql`

```sql
USE imartap;

INSERT IGNORE INTO promo_codes
  (code, type, discount_value, voucher_remainer,
   max_uses, active,
   expiration_date, created_at, used_at,
   source, note, site, created_by)
SELECT
   kod,
   CASE tip WHEN 0 THEN 'fixed' WHEN 1 THEN 'percent' WHEN 2 THEN 'shipping' ELSE 'percent' END,
   CAST(value AS DECIMAL(10,2)),
   CASE WHEN tip = 0 THEN CAST(value AS DECIMAL(10,2)) ELSE NULL END,
   1,
   IF(izpolzvan = '1', 0, 1),
   data_validen,
   data_sazdaden,
   data_izpolzvan,
   'the-marketer',
   komentar,
   sait,
   COALESCE(NULLIF(ot_kade, ''), 'the-marketer')
FROM loyality_points
WHERE kod IS NOT NULL AND kod <> ''
  AND tip IN (0, 1, 2);
```

### `old/06-migrate-obshti_kodove.sql`

```sql
USE imartap;

INSERT IGNORE INTO promo_codes
  (code, type, discount_value, voucher_remainer,
   max_uses, active,
   expiration_date, created_at, used_at,
   source, note, site, created_by)
SELECT
   kod,
   CASE tip WHEN 0 THEN 'fixed' WHEN 1 THEN 'percent' WHEN 2 THEN 'shipping' ELSE 'percent' END,
   CAST(value AS DECIMAL(10,2)),
   CASE WHEN tip = 0 THEN CAST(value AS DECIMAL(10,2)) ELSE NULL END,
   0,
   1,
   data_validen,
   data_sazdaden,
   NULL,
   'manual',
   komentar,
   sait,
   NULLIF(ot_kade, '')
FROM obshti_kodove
WHERE kod IS NOT NULL AND kod <> ''
  AND tip IN (0, 1, 2);
```

### `old/07-verification.sql`

```sql
USE imartap;

SELECT
   (SELECT COUNT(*) FROM loyality_points)                          AS loyality_total,
   (SELECT COUNT(*) FROM obshti_kodove)                            AS obshti_total,
   (SELECT COUNT(*) FROM promo_codes)                              AS promo_total,
   (SELECT COUNT(*) FROM promo_codes WHERE source='the-marketer')  AS from_marketer,
   (SELECT COUNT(*) FROM promo_codes WHERE source='manual')        AS from_manual,
   (SELECT COUNT(*) FROM promo_codes WHERE source='bulk-import')   AS from_bulk;

SELECT 'missing from loyality' AS lbl, l.id, l.kod
  FROM loyality_points l
  LEFT JOIN promo_codes p ON p.code = l.kod
  WHERE p.id IS NULL AND l.kod IS NOT NULL AND l.kod <> ''
UNION ALL
SELECT 'missing from obshti' AS lbl, o.id, o.kod
  FROM obshti_kodove o
  LEFT JOIN promo_codes p ON p.code = o.kod
  WHERE p.id IS NULL AND o.kod IS NOT NULL AND o.kod <> '';

SELECT id, code, type, discount_value, voucher_remainer, max_uses, active,
       expiration_date, created_at, used_at, source, created_by, note
FROM promo_codes
WHERE code IN ('VELIKDEN10','slujeben10','SPRING10EM26','svet25evro','svet10procenta','kod0','kod1')
ORDER BY source, code;

SELECT source, type, COUNT(*) AS cnt
FROM promo_codes
GROUP BY source, type
ORDER BY source, type;

SELECT source, active, COUNT(*) AS cnt
FROM promo_codes
GROUP BY source, active
ORDER BY source, active;

SELECT 'voucher_remainer set for non-fixed' AS lbl, COUNT(*) AS cnt
FROM promo_codes
WHERE voucher_remainer IS NOT NULL AND type <> 'fixed';

SELECT 'fixed type without voucher_remainer' AS lbl, COUNT(*) AS cnt
FROM promo_codes
WHERE type = 'fixed' AND voucher_remainer IS NULL;

SELECT 'rows missing created_at' AS lbl, COUNT(*) AS cnt
FROM promo_codes
WHERE created_at IS NULL OR created_at = '';

SELECT
   l.kod                            AS source_kod,
   l.tip                            AS source_tip,
   l.value                          AS source_value,
   p.code                           AS promo_code,
   p.type                           AS promo_type,
   p.discount_value                 AS promo_discount,
   p.voucher_remainer               AS promo_voucher,
   p.source                         AS promo_source
FROM loyality_points l
JOIN promo_codes p ON p.code = l.kod
ORDER BY l.id
LIMIT 5;
```

### `old/08-add-phase2-columns.sql`

```sql
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l' AND COLUMN_NAME = 'discount_applied'),
  'ALTER TABLE `item_l` ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT ''Phase 2 promo discount on the line (audit)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no' AND COLUMN_NAME = 'discount_applied'),
  'ALTER TABLE `item_no` ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT ''Phase 2 promo discount on the line (audit)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item' AND COLUMN_NAME = 'discount_applied'),
  'ALTER TABLE `item` ADD COLUMN `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT ''Phase 2 promo discount on the line (audit)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki' AND COLUMN_NAME = 'pordost_coupon_discount'),
  'ALTER TABLE `porachki` ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT ''Shipping promo discount (audit/UI)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_l' AND COLUMN_NAME = 'pordost_coupon_discount'),
  'ALTER TABLE `porachki_l` ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT ''Shipping promo discount (audit/UI)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_no' AND COLUMN_NAME = 'pordost_coupon_discount'),
  'ALTER TABLE `porachki_no` ADD COLUMN `pordost_coupon_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT ''Shipping promo discount (audit/UI)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
```

### `old/09-drop-per-site-promo-tables.sql`

```sql
SET FOREIGN_KEY_CHECKS = 0;

SET @ddl := IF(DATABASE() <> 'imartap', 'DROP TABLE IF EXISTS `cart_promo_codes`', 'DO 0');
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := IF(DATABASE() <> 'imartap', 'DROP TABLE IF EXISTS `order_promo_codes`', 'DO 0');
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := IF(DATABASE() <> 'imartap', 'DROP TABLE IF EXISTS `promo_codes`', 'DO 0');
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET FOREIGN_KEY_CHECKS = 1;
```

### `old/10-verify-phase2.sql`

```sql
SELECT TABLE_NAME, COLUMN_NAME, COLUMN_TYPE, COLUMN_DEFAULT
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND ((TABLE_NAME IN ('item','item_l','item_no')        AND COLUMN_NAME = 'discount_applied')
    OR (TABLE_NAME IN ('porachki','porachki_l','porachki_no') AND COLUMN_NAME = 'pordost_coupon_discount'))
ORDER BY TABLE_NAME;

SELECT DATABASE() AS db,
       SUM(TABLE_NAME = 'promo_codes')       AS has_promo_codes,
       SUM(TABLE_NAME = 'cart_promo_codes')  AS has_cart_promo_codes,
       SUM(TABLE_NAME = 'order_promo_codes') AS has_order_promo_codes
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('promo_codes','cart_promo_codes','order_promo_codes');
```

### `old/11-add-used-by-employee.sql`

```sql
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'order_promo_codes')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'order_promo_codes' AND COLUMN_NAME = 'used_by_employeeId'),
  'ALTER TABLE `order_promo_codes` ADD COLUMN `used_by_employeeId` INT NULL DEFAULT NULL COMMENT ''Employee who used the code (admin/backoffice app; legacy obshti_kodove.potrebitel)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
```

### `old/12-add-baza-columns.sql`

```sql
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l' AND COLUMN_NAME = 'it_suma_baza'),
  'ALTER TABLE `item_l` ADD COLUMN `it_cena_baza` FLOAT NULL DEFAULT NULL COMMENT ''Phase 1 unit price (frozen cenni, pre-promo)'', ADD COLUMN `it_suma_baza` FLOAT NULL DEFAULT NULL COMMENT ''Phase 1 line total (frozen cenni, pre-promo)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_l' AND COLUMN_NAME = 'it_suma_baza'),
  'UPDATE `item_l` SET `it_suma_baza` = `it_suma` + `discount_applied`, `it_cena_baza` = (`it_suma` + `discount_applied`) / GREATEST(`item_br`, 1) WHERE `it_suma_baza` IS NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no' AND COLUMN_NAME = 'it_suma_baza'),
  'ALTER TABLE `item_no` ADD COLUMN `it_cena_baza` FLOAT NULL DEFAULT NULL COMMENT ''Phase 1 unit price (frozen cenni, pre-promo)'', ADD COLUMN `it_suma_baza` FLOAT NULL DEFAULT NULL COMMENT ''Phase 1 line total (frozen cenni, pre-promo)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item_no' AND COLUMN_NAME = 'it_suma_baza'),
  'UPDATE `item_no` SET `it_suma_baza` = `it_suma` + `discount_applied`, `it_cena_baza` = (`it_suma` + `discount_applied`) / GREATEST(`item_br`, 1) WHERE `it_suma_baza` IS NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item' AND COLUMN_NAME = 'it_suma_baza'),
  'ALTER TABLE `item` ADD COLUMN `it_cena_baza` FLOAT NULL DEFAULT NULL COMMENT ''Phase 1 unit price (frozen cenni, pre-promo)'', ADD COLUMN `it_suma_baza` FLOAT NULL DEFAULT NULL COMMENT ''Phase 1 line total (frozen cenni, pre-promo)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'item' AND COLUMN_NAME = 'it_suma_baza'),
  'UPDATE `item` SET `it_suma_baza` = `it_suma` + `discount_applied`, `it_cena_baza` = (`it_suma` + `discount_applied`) / GREATEST(`item_br`, 1) WHERE `it_suma_baza` IS NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
```

### `old/13-add-promo-fixed-discount-cart.sql`

```sql
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_l')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_l' AND COLUMN_NAME = 'promo_fixed_discount'),
  'ALTER TABLE `porachki_l` ADD COLUMN `promo_fixed_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT ''Order-level fixed/voucher promo total on the cart (mini-cart net display)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_no')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'porachki_no' AND COLUMN_NAME = 'promo_fixed_discount'),
  'ALTER TABLE `porachki_no` ADD COLUMN `promo_fixed_discount` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT ''Order-level fixed/voucher promo total on the cart (mini-cart net display)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
```

### `old/14-create-cart_promo_codes-regional.sql`

```sql
CREATE TABLE IF NOT EXISTS `cart_promo_codes` (
  `id`               INT           NOT NULL AUTO_INCREMENT,
  `cart_id`          INT           NOT NULL,
  `cart_type`        ENUM('l','no') NOT NULL COMMENT 'l = porachki_l logged-in, no = porachki_no guest',
  `promo_code_id`    INT           NOT NULL COMMENT 'imartap.promo_codes.id (no cross-DB FK)',
  `code`             VARCHAR(50)   NOT NULL,
  `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '0 for shipping types; real deduction for percent/fixed',
  `type`             ENUM('percent','fixed','shipping','shipping_percent') NOT NULL,
  `shipping_cap`     DECIMAL(10,2) NULL DEFAULT NULL COMMENT 'shipping/shipping_percent only (flat cap on the discount)',
  `created_at`       VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_cart_promo` (`cart_id`, `cart_type`, `promo_code_id`),
  KEY `idx_promo_code` (`promo_code_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### `old/15-create-order_promo_codes-regional.sql`

```sql
CREATE TABLE IF NOT EXISTS `order_promo_codes` (
  `id`                 INT           NOT NULL AUTO_INCREMENT,
  `order_id`           INT           NOT NULL COMMENT 'porachki.porachki_id',
  `promo_code_id`      INT           NOT NULL COMMENT 'imartap.promo_codes.id (no cross-DB FK)',
  `klienti_id`         INT           NOT NULL DEFAULT 0 COMMENT '0 = guest',
  `discount_applied`   DECIMAL(10,2) NOT NULL,
  `used_by_employeeId` INT           NULL DEFAULT NULL COMMENT 'admin/backoffice app; storefront leaves NULL',
  `created_at`         VARCHAR(14)   NOT NULL COMMENT 'YYYYMMDDHHmmss',

  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_order_promo` (`order_id`, `promo_code_id`),
  KEY `idx_klienti` (`klienti_id`, `promo_code_id`),
  KEY `idx_promo_code` (`promo_code_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### `old/16-add-shipping_percent-type.sql`

```sql
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'promo_codes')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'promo_codes'
             AND COLUMN_NAME = 'type' AND COLUMN_TYPE LIKE '%shipping_percent%'),
  'ALTER TABLE `promo_codes` MODIFY COLUMN `type` ENUM(''percent'',''fixed'',''shipping'',''shipping_percent'') NOT NULL DEFAULT ''percent''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;

SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cart_promo_codes')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cart_promo_codes'
             AND COLUMN_NAME = 'type' AND COLUMN_TYPE LIKE '%shipping_percent%'),
  'ALTER TABLE `cart_promo_codes` MODIFY COLUMN `type` ENUM(''percent'',''fixed'',''shipping'',''shipping_percent'') NOT NULL',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
```

### `old/17-drop-imartap-cart_promo_codes.sql`

```sql
SET @ddl := IF(DATABASE() = 'imartap', 'DROP TABLE IF EXISTS `cart_promo_codes`', 'DO 0');
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
```

### `old/18-add-cart_promo_codes-discount_value.sql`

```sql
ALTER TABLE cart_promo_codes
  ADD COLUMN IF NOT EXISTS `discount_value` DECIMAL(10,2) NOT NULL DEFAULT 0.00
    COMMENT 'Snapshot of promo_codes.discount_value at apply-time (% or lv.); avoids cross-host catalog read at recalc/finalize'
    AFTER `discount_applied`;
```

### `old/19-add-subtype.sql`

```sql
ALTER TABLE promo_codes
    ADD COLUMN IF NOT EXISTS `subtype` ENUM('voucher','coupon') NULL DEFAULT NULL AFTER `type`;

ALTER TABLE cart_promo_codes
    ADD COLUMN IF NOT EXISTS `subtype` ENUM('voucher','coupon') NULL DEFAULT NULL AFTER `type`;
```

