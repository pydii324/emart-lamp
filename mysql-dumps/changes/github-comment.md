# Промо схема — 37 региона, 18 валути, EUR база

ALTER миграции за база с **вече съществуващи** промо таблици. Не е инсталация от нула —
за нея виж `mysql-dumps/promo_codes/fresh/`.

Файловете (с пълните коментари и обяснения): `mysql-dumps/changes/` + `README.md` там.

### Baseline → край

|     |     |     |
| --- | --- | --- |
| Колона | От | До |
| `promo_codes.site` | `VARCHAR(10)` или `ENUM('bg','ro','gr','al')` | `ENUM(37 региона) NULL` |
| `promo_codes.currency` | `ENUM('BGN','EUR','ALL','RON') DEFAULT 'BGN'` | `ENUM(18 валути) DEFAULT 'EUR'` |
| `cart_promo_codes.currency` | същите 4 | същите 18 |
| `order_promo_codes.currency` | същите 4 | същите 18 |
| `currency_rates` | `rate_to_bgn`, база BGN, 4 реда | `rate_to_eur`, база EUR, 18 реда |

Регионите са байт-идентични с `PromoCode::SITES`, валутите — с `PromoCode::SITE_CURRENCY`.

### Ред на пускане

```
imartap:      00 → 01 → 02 → 03 → 04 → 05 → 07
регионална:   00 → 05 → 06 → 07          (по веднъж за всеки регион)
```

- **01 преди 02** — 02 пише `rate_to_eur`; иначе `ERROR 1054`.
- **03 преди 04** — 04 стеснява `site` до ENUM; стойност извън списъка се губи. 03 я мести на `NULL`, докато колоната още я побира.
- `--force` **само** за 00 и 07 (read-only). Никога на 01–06 — спрелият run е сигналът.
- `04` иска utf8mb4 клиент (кирилски COMMENT).

### Миграции

<details>
<summary><b>00-preflight.sql</b> — read-only, доказва baseline-а · imartap + регионална</summary>

```sql
SELECT DATABASE() AS `db`, VERSION() AS `mysql_version`, NOW() AS `checked_at`;

SELECT
  'A. promo tables present' AS `check`,
  TABLE_NAME                AS `table`,
  TABLE_ROWS                AS `approx_rows`
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN ('promo_codes','cart_promo_codes','order_promo_codes','currency_rates')
ORDER BY TABLE_NAME;

SELECT
  'B. rate column'  AS `check`,
  COLUMN_NAME       AS `column`,
  COLUMN_TYPE       AS `type`,
  CASE COLUMN_NAME
    WHEN 'rate_to_bgn' THEN 'OK — on the old base, run 01'
    ELSE 'ALREADY DONE — 01 has run here, skip it'
  END AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME  = 'currency_rates'
  AND COLUMN_NAME IN ('rate_to_bgn','rate_to_eur');

SELECT
  'C. site column'  AS `check`,
  DATA_TYPE         AS `data_type`,
  IS_NULLABLE       AS `nullable`,
  (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 AS `values`,
  COLUMN_TYPE       AS `declared_as`,
  CASE
    WHEN DATA_TYPE <> 'enum' THEN 'OK — VARCHAR baseline, nothing enforced yet'
    WHEN (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 = 37
      THEN 'ALREADY DONE — 04 has run here'
    WHEN COLUMN_TYPE LIKE 'enum(\'bg\',\'ro\',\'gr\',\'al\')%'
      THEN 'OK — four-region ENUM baseline'
    ELSE 'FAIL — unexpected shape, reconcile by hand before running 04'
  END AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'promo_codes' AND COLUMN_NAME = 'site';

SELECT
  'D. currency ENUM' AS `check`,
  TABLE_NAME         AS `table`,
  (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 AS `values`,
  COLUMN_DEFAULT     AS `default`,
  COLUMN_TYPE        AS `declared_as`,
  CASE
    WHEN DATA_TYPE <> 'enum' THEN CONCAT('FAIL — not an ENUM: ', COLUMN_TYPE)
    WHEN (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 = 18
      THEN 'ALREADY DONE — this table has been widened'
    WHEN (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 = 4
      THEN 'OK — four-currency baseline'
    ELSE 'FAIL — unexpected width, reconcile by hand'
  END AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND COLUMN_NAME = 'currency'
  AND TABLE_NAME IN ('promo_codes','cart_promo_codes','order_promo_codes')
ORDER BY TABLE_NAME;

SELECT
  'E. original values first' AS `check`,
  TABLE_NAME                 AS `table`,
  COLUMN_NAME                AS `column`,
  LEFT(COLUMN_TYPE, 40)      AS `starts_with`,
  IF(DATA_TYPE <> 'enum', 'n/a (not an ENUM)',
     IF(COLUMN_TYPE LIKE
          IF(COLUMN_NAME = 'site', 'enum(\'bg\',\'ro\',\'gr\',\'al\'%', 'enum(\'BGN\',\'EUR\',\'ALL\',\'RON\'%'),
        'OK', 'WARN — order drifted; conversion is still value-safe but costs a table copy')) AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND ((TABLE_NAME = 'promo_codes' AND COLUMN_NAME IN ('site','currency'))
    OR (TABLE_NAME IN ('cart_promo_codes','order_promo_codes') AND COLUMN_NAME = 'currency'))
ORDER BY TABLE_NAME, COLUMN_NAME;

SELECT
  'F. promo_codes unique keys' AS `check`,
  INDEX_NAME                   AS `index`,
  GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX SEPARATOR ', ') AS `columns`,
  CASE INDEX_NAME
    WHEN 'uq_code_site' THEN 'OK — one code per region'
    WHEN 'PRIMARY'      THEN 'n/a — surrogate key'
    ELSE 'INFO — still one code globally; see deploy/09 (independent of this set)'
  END AS `result`
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'promo_codes'
  AND NON_UNIQUE = 0
GROUP BY INDEX_NAME
ORDER BY INDEX_NAME;

SELECT
  'G. rows to be parked on NULL' AS `check`,
  `site`                         AS `current_site`,
  `active`,
  COUNT(*)                       AS `rows`,
  GROUP_CONCAT(`code` ORDER BY `code` SEPARATOR ', ') AS `codes`
FROM `promo_codes`
WHERE `site` IS NULL
   OR `site` NOT IN ('bg','ro','gr','al',
                     'en','md','at','cz','de','es','hr','hu','it','pl','si','sk','cy','uk','us','co',
                     'be','dk','ee','fi','fr','lt','lv','nl','pt','se','mk','rs','ua','tr','ru',
                     'biz','org')
GROUP BY `site`, `active`
ORDER BY `active` DESC, `rows` DESC;

SELECT
  'H. before → after'               AS `check`,
  `currency`,
  `rate_to_bgn`                     AS `now_in_bgn`,
  ROUND(`rate_to_bgn` / 1.95583, 8) AS `becomes_in_eur`,
  `is_fixed`,
  `source`
FROM `currency_rates`
ORDER BY `is_fixed` DESC, `currency`;

SELECT 'I. new-currency rows already present' AS `check`,
       `currency`, `rate_to_bgn`, `is_fixed`, `source`, `updated_at`
FROM `currency_rates`
WHERE `currency` IN ('CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD',
                     'RUB','SEK','TRY','UAH','USD','CAD')
ORDER BY `currency`;
```

</details>

<details>
<summary><b>01-rebase-currency-rates-to-eur.sql</b> — `rate_to_bgn` → `rate_to_eur`, ÷ 1.95583 · imartap</summary>

```sql
ALTER TABLE `currency_rates`
  CHANGE `rate_to_bgn` `rate_to_eur` DECIMAL(18,8) NOT NULL
    COMMENT '1 unit of `currency` = rate_to_eur EUR';

UPDATE `currency_rates`
   SET `rate_to_eur` = ROUND(`rate_to_eur` / 1.95583, 8);

UPDATE `currency_rates`
   SET `rate_to_eur` = 1.00000000, `is_fixed` = 1, `source` = 'fixed'
 WHERE `currency` = 'EUR';

UPDATE `currency_rates`
   SET `rate_to_eur` = 0.51129188, `is_fixed` = 1, `source` = 'fixed'
 WHERE `currency` = 'BGN';
```

</details>

<details>
<summary><b>02-seed-new-currency-rates.sql</b> — 14 нови реда в `currency_rates` · imartap</summary>

```sql
INSERT INTO `currency_rates` (`currency`, `rate_to_eur`, `is_fixed`, `source`, `updated_at`) VALUES
  ('CZK', 0.04049432, 0, 'bnb',    NULL),
  ('DKK', 0.13406073, 0, 'bnb',    NULL),
  ('GBP', 1.17085841, 0, 'bnb',    NULL),
  ('HUF', 0.00255646, 0, 'bnb',    NULL),
  ('MDL', 0.05061790, 0, 'manual', NULL),
  ('MKD', 0.01625908, 0, 'manual', NULL),
  ('PLN', 0.23519427, 0, 'bnb',    NULL),
  ('RSD', 0.00853857, 0, 'manual', NULL),
  ('RUB', 0.01048148, 0, 'bnb',    NULL),
  ('SEK', 0.08947608, 0, 'bnb',    NULL),
  ('TRY', 0.02403072, 0, 'bnb',    NULL),
  ('UAH', 0.02147426, 0, 'bnb',    NULL),
  ('USD', 0.85897036, 0, 'bnb',    NULL),
  ('CAD', 0.64934069, 0, 'bnb',    NULL);
```

</details>

<details>
<summary><b>03-park-unconvertible-sites.sql</b> — не-регионите → `NULL`, старото в `note` · imartap</summary>

```sql
UPDATE `promo_codes`
   SET `note` = LEFT(CONCAT('[retired site=', `site`, '] ', COALESCE(`note`, '')), 255)
 WHERE `site` IS NOT NULL
   AND `site` NOT IN ('bg','ro','gr','al',
                      'en','md','at','cz','de','es','hr','hu','it','pl','si','sk','cy','uk','us','co',
                      'be','dk','ee','fi','fr','lt','lv','nl','pt','se','mk','rs','ua','tr','ru',
                      'biz','org');

UPDATE `promo_codes`
   SET `active` = 0
 WHERE `active` = 1
   AND (`site` IS NULL
    OR  `site` NOT IN ('bg','ro','gr','al',
                       'en','md','at','cz','de','es','hr','hu','it','pl','si','sk','cy','uk','us','co',
                       'be','dk','ee','fi','fr','lt','lv','nl','pt','se','mk','rs','ua','tr','ru',
                       'biz','org'));

UPDATE `promo_codes`
   SET `site` = NULL
 WHERE `site` NOT IN ('bg','ro','gr','al',
                      'en','md','at','cz','de','es','hr','hu','it','pl','si','sk','cy','uk','us','co',
                      'be','dk','ee','fi','fr','lt','lv','nl','pt','se','mk','rs','ua','tr','ru',
                      'biz','org');
```

</details>

<details>
<summary><b>04-extend-promo_codes-enums.sql</b> — `site` → 37, `currency` → 18 · imartap</summary>

```sql
SET NAMES utf8mb4;

ALTER TABLE `promo_codes`
  MODIFY `currency` ENUM('BGN','EUR','ALL','RON',
                         'CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD','RUB','SEK','TRY','UAH','USD','CAD')
                    NOT NULL DEFAULT 'EUR'
                    COMMENT 'code currency (ALL = Albanian lek, RON = Romanian leu, MDL = Moldovan leu, MKD = Macedonian denar, RSD = Serbian dinar)',
  MODIFY `site`     ENUM('bg','ro','gr','al',
                         'en','md','at','cz','de','es','hr','hu','it','pl','si','sk','cy','uk','us','co',
                         'be','dk','ee','fi','fr','lt','lv','nl','pt','se','mk','rs','ua','tr','ru',
                         'biz','org')
                    NULL DEFAULT NULL
                    COMMENT 'регионът, за който важи кодът — по един на код, без wildcard (виж PromoCode::SITES). NULL = архивен ред, не се осребрява никъде';
```

</details>

<details>
<summary><b>05-extend-order_promo_codes-currency.sql</b> — `currency` → 18 · imartap И регионална</summary>

```sql
ALTER TABLE `order_promo_codes`
  MODIFY `currency` ENUM('BGN','EUR','ALL','RON',
                         'CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD','RUB','SEK','TRY','UAH','USD','CAD')
                    NOT NULL DEFAULT 'EUR'
                    COMMENT 'snapshot of promo_codes.currency at order-finalize';
```

</details>

<details>
<summary><b>06-extend-cart_promo_codes-currency.sql</b> — `currency` → 18 · само регионална</summary>

```sql
ALTER TABLE `cart_promo_codes`
  MODIFY `currency` ENUM('BGN','EUR','ALL','RON',
                         'CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD','RUB','SEK','TRY','UAH','USD','CAD')
                    NOT NULL DEFAULT 'EUR'
                    COMMENT 'snapshot of promo_codes.currency at apply-time';
```

</details>

<details>
<summary><b>07-verify.sql</b> — read-only, какво реално е кацнало · imartap + регионална</summary>

```sql
SELECT DATABASE() AS `db`, NOW() AS `verified_at`;

SELECT
  'A. enum width' AS `check`,
  TABLE_NAME      AS `table`,
  COLUMN_NAME     AS `column`,
  (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 AS `values`,
  COLUMN_DEFAULT  AS `default`,
  IS_NULLABLE     AS `nullable`,
  CASE
    WHEN DATA_TYPE <> 'enum'                                   THEN CONCAT('FAIL — not an ENUM: ', COLUMN_TYPE)
    WHEN COLUMN_NAME = 'site' AND COLUMN_TYPE LIKE '%\'all\'%' THEN 'FAIL — retired wildcard still declared'
    WHEN COLUMN_NAME = 'site'
         AND (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 <> 37
      THEN 'FAIL — region list out of sync with PromoCode::SITES (04 not run?)'
    WHEN COLUMN_NAME = 'currency'
         AND (LENGTH(COLUMN_TYPE) - LENGTH(REPLACE(COLUMN_TYPE, ',', ''))) + 1 <> 18
      THEN 'FAIL — missing a currency (04/05/06 not run on this table?)'
    WHEN COLUMN_NAME = 'currency' AND COLUMN_DEFAULT <> 'EUR'
      THEN 'FAIL — DEFAULT still on the old base currency'
    ELSE 'OK'
  END AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND ((TABLE_NAME = 'promo_codes' AND COLUMN_NAME IN ('site','currency'))
    OR (TABLE_NAME IN ('cart_promo_codes','order_promo_codes') AND COLUMN_NAME = 'currency'))
ORDER BY TABLE_NAME, COLUMN_NAME;

SELECT
  'B. original values first' AS `check`,
  TABLE_NAME                 AS `table`,
  COLUMN_NAME                AS `column`,
  LEFT(COLUMN_TYPE, 40)      AS `starts_with`,
  IF(COLUMN_TYPE LIKE
       IF(COLUMN_NAME = 'site', 'enum(\'bg\',\'ro\',\'gr\',\'al\',%', 'enum(\'BGN\',\'EUR\',\'ALL\',\'RON\',%'),
     'OK', 'WARN — declaration order drifted from every other instance') AS `result`
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND ((TABLE_NAME = 'promo_codes' AND COLUMN_NAME IN ('site','currency'))
    OR (TABLE_NAME IN ('cart_promo_codes','order_promo_codes') AND COLUMN_NAME = 'currency'))
ORDER BY TABLE_NAME, COLUMN_NAME;

SELECT
  'C. truncated to empty' AS `check`,
  COUNT(*)                AS `rows`,
  IF(COUNT(*) = 0, 'OK', 'FAIL — 03 was skipped before 04, values were lost') AS `result`
FROM `promo_codes`
WHERE `site` = '' OR `currency` = '';

SELECT
  'D. site values in use'             AS `check`,
  COALESCE(`site`, '(NULL — parked)') AS `region`,
  `active`,
  COUNT(*)                            AS `rows`,
  CASE
    WHEN `site` IS NOT NULL THEN 'OK'
    WHEN `active` = 0       THEN 'parked — unredeemable by design, kept for audit'
    ELSE 'FAIL — active code with no region, it can never be redeemed'
  END AS `result`
FROM `promo_codes`
GROUP BY `site`, `active`
ORDER BY `rows` DESC;

SELECT 'E. currency_rates' AS `check`,
       `currency`, `rate_to_eur`, `is_fixed`, `source`, `updated_at`
FROM `currency_rates`
ORDER BY `is_fixed` DESC, `currency`;

SELECT
  'E2. fixed anchors' AS `check`,
  `currency`,
  `rate_to_eur`,
  `is_fixed`,
  `source`,
  CASE
    WHEN `currency` = 'EUR' AND `rate_to_eur` = 1.00000000 AND `is_fixed` = 1 AND `source` = 'fixed' THEN 'OK'
    WHEN `currency` = 'BGN' AND `rate_to_eur` = 0.51129188 AND `is_fixed` = 1 AND `source` = 'fixed' THEN 'OK'
    ELSE 'FAIL — anchor rate, is_fixed or source is wrong (01 not run / half-run?)'
  END AS `result`
FROM `currency_rates`
WHERE `currency` IN ('EUR','BGN')
ORDER BY `currency`;

SELECT
  'E3. magnitudes' AS `check`,
  `currency`,
  `rate_to_eur`,
  CASE
    WHEN `currency` = 'GBP' AND `rate_to_eur` BETWEEN 0.8 AND 2.0 THEN 'OK'
    WHEN `currency` = 'GBP'                                       THEN 'FAIL — GBP out of range, still leva-based?'
    WHEN `rate_to_eur` >= 1.5                                     THEN 'WARN — suspiciously large for a EUR-based rate'
    ELSE 'OK'
  END AS `result`
FROM `currency_rates`
ORDER BY `rate_to_eur` DESC;

SELECT
  'F. fixed vs fetchable' AS `check`,
  `is_fixed`,
  `source`,
  COUNT(*)                AS `rows`,
  GROUP_CONCAT(`currency` ORDER BY `currency` SEPARATOR ', ') AS `currencies`,
  CASE
    WHEN `is_fixed` = 1 AND `source` <> 'fixed' THEN 'FAIL — fixed row not marked source=fixed'
    WHEN `is_fixed` = 0 AND `source`  = 'fixed' THEN 'FAIL — source=fixed but the job may overwrite it'
    ELSE 'OK'
  END AS `result`
FROM `currency_rates`
GROUP BY `is_fixed`, `source`
ORDER BY `is_fixed` DESC, `source`;

SELECT
  'G. currency without a rate' AS `check`,
  p.`currency`,
  COUNT(*)                     AS `codes`,
  'FAIL — add a currency_rates row before authoring in this currency' AS `result`
FROM `promo_codes` p
WHERE NOT EXISTS (SELECT 1 FROM `currency_rates` r WHERE r.`currency` = p.`currency`)
GROUP BY p.`currency`;
```

</details>

### Курсове — кое се обновява само и кое не

`scripts/update-currency-rates.php` (cron, BNB daily fixing) пипа **само** редове с
`is_fixed = 0 AND source = 'bnb'`. Проверено срещу живия feed — той носи 29 валути:

| Валута | source | Обновява ли се |
| --- | --- | --- |
| EUR, BGN | `fixed` | Не — законово фиксирани (база 1.0 / 0.51129188) |
| CZK, DKK, GBP, HUF, PLN, RON, SEK, TRY, USD, CAD | `bnb` | ✅ при първия cron |
| **ALL**, MDL, MKD, RSD | `manual` | Не — BNB не ги публикува, ръчно |
| RUB, UAH | `bnb` | ⚠️ BNB вече не ги листва → `WARN: provider had no rate for: RUB, UAH` на всеки run, стойността се пази. Ако не искаш шума — сложи ги на `manual` |

**Албания:** `ALL` **вече е в baseline-а** — старият ENUM е `('BGN','EUR','ALL','RON')` и
редът е добавен още в `deploy/07`. Затова `02` нарочно не го включва: `INSERT`-ът е
атомичен и един `ERROR 1062` за `ALL` би отменил и другите 14 реда. `01` го ре-базира
както всичко останало — `0.01960000 BGN ÷ 1.95583 = 0.01002132 EUR`.

За инстанция, която наистина няма реда (отпреди `deploy/07`), в `02` има закоментиран
единичен `INSERT` — разкоментирай го след `SELECT * FROM currency_rates WHERE currency='ALL';`.

⚠️ Курсът на лека е **placeholder** (≈ 99.8 лека за EUR) и никой job няма да го оправи.
Сложи реален курс от БНБ на Албания преди да се авторира `fixed` ALL код.

### ⚠️ Не конвертира записаните суми

`01` ре-базира само таблицата с курсове. Голите парични колони нямат собствена валута —
`cart_promo_codes.discount_value`, `order_promo_codes.discount_applied`,
`porachki.pordost_coupon_discount` / `promo_fixed_discount` — така че стара поръчка се чете
**1.95583× по-голяма**. Редовете в `promo_codes` са наред (носят си `currency`).
Отделна data миграция със свой cut-over.

Извън scope и **не** се пипат: `subtype`, `shipping_percent`, FK-ите, промо колоните по
`item*`/`porachki*`, промо SKU-тата. Приемат се за налични.

### Ако гръмне

Гол SQL спира на проблемния statement и оставя предходните приложени. Пусни `07-verify.sql`.

|     |     |
| --- | --- |
| Грешка | Значение |
| `1054 Unknown column 'rate_to_bgn'` | 01 вече е минал — прескочи го |
| `1054 Unknown column 'rate_to_eur'` | 02 преди 01 |
| `1062 Duplicate entry` | 02 вече е минал (`00` check I го показва) |
| `1146 Table doesn't exist` | Грешен target — 06 срещу imartap, или 01–04 срещу регионална |
| `1265 Data truncated for column 'site'` | 04 без 03. Под STRICT ALTER-ът се отхвърля и нищо не се губи — пусни 03 и повтори |

`03`–`06` не гърмят при повторение (`UPDATE` хваща 0 реда, `MODIFY` предеклирира същия тип).
Сигналът за състояние там е `00-preflight`.

### Тествано

End-to-end на dev (`lamp-mysql8`, MySQL 8.4.9), throwaway бази — `imartap`/`inmarta` не са пипани.

- И двата baseline варианта (`site` VARCHAR и 4-регионален ENUM) минават чисто.
- Крайната схема е идентична с `fresh/` инсталация по ENUM стойности, ред и `DEFAULT`. Разликите са двете нарочни: `site` е NULLable и коментарът има суфикс за `NULL`.
- Дрейфнал cron курс се пази: RON 0.39352 → `0.20120358`, не placeholder-ът. Затова `01` дели в SQL вместо да пише литерали.
- Паркиране: 5 реда → `NULL`, всички inactive, старото в `note`; ред с note вече на 255 знака пази маркера отпред.
- Кирилският COLUMN COMMENT каца без mojibake.
- Всяка грешка от таблицата горе е възпроизведена.
