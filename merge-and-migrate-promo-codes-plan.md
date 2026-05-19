# План: обединяване на `loyality_points` + `obshti_kodove`, после еволюция към `promo_codes`

Разделено на два phase-а:
- **Phase 1** — обединяване на двете стари таблици в една (`obshti_kodove`).
- **Phase 2** — еволюция на унифицираната таблица към shape-а на новата `promo_codes`.

---

# Phase 1: обединяване в една таблица (междинна стъпка)

## Избор на име

Препоръка: **запазваме `obshti_kodove`** (а не нова таблица). Причини:
- Тя има повече и по-разнообразни данни (named campaign codes), които ще трябва да оцелеят.
- Не променяме PK-ите на запазените редове — по-нисък риск.
- Името „общи кодове" пасва семантично на унифицираната таблица.

`loyality_points` редовете се вливат в нея, после `loyality_points` се DROP-ва.

## Целева схема на унифицираната `obshti_kodove`

```sql
CREATE TABLE `obshti_kodove` (
  `id`              INT          NOT NULL AUTO_INCREMENT,
  `ot_kade`         VARCHAR(255) NOT NULL,                       -- запазен (free-form: 'the-marketer','ivo','ЦГ2',…)
  `generated_from`  ENUM('the-marketer','manual') NOT NULL DEFAULT 'manual',  -- структуриран произход
  `kod`             VARCHAR(255) NOT NULL,
  `sait`            VARCHAR(255) NULL,
  `data_sazdaden`   VARCHAR(255) NOT NULL,
  `data_validen`    VARCHAR(255) NULL,
  `data_izpolzvan`  VARCHAR(255) NULL,                           -- ✱ ново за obshti, идва от loyality
  `izpolzvan_pati`  INT          NOT NULL DEFAULT 0,             -- counter
  `max_uses`        INT          NOT NULL DEFAULT 0,             -- ✱ ново: 0 = безлимит; 1 = single-use (бившите loyality)
  `tip`             SMALLINT     NULL,                           -- 0=fixed, 1=percent, 2=shipping
  `value`           FLOAT        NOT NULL DEFAULT 0,
  `komentar`        VARCHAR(255) NULL,
  `potrebitel`      INT          NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `kod` (`kod`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

Три нови колони спрямо текущата `obshti_kodove`:
- `generated_from` — default `manual` (точно за Excel bulk import use case).
- `data_izpolzvan` — за съвместимост с `loyality_points` (last usage timestamp).
- `max_uses` — отличава single-use codes (бившите `loyality_points`, `1`) от multi-use (бившите `obshti_kodove`, `0`).

## Migration стъпки

```sql
-- 1. Разширяваме obshti_kodove
ALTER TABLE obshti_kodove
  ADD COLUMN generated_from ENUM('the-marketer','manual') NOT NULL DEFAULT 'manual' AFTER ot_kade,
  ADD COLUMN data_izpolzvan VARCHAR(255) NULL AFTER data_validen,
  ADD COLUMN max_uses INT NOT NULL DEFAULT 0 AFTER izpolzvan_pati;

-- 2. Маркираме всички съществуващи obshti_kodove редове като manual
--    (generated_from вече има DEFAULT 'manual' — explicit UPDATE за яснота)
UPDATE obshti_kodove SET generated_from = 'manual' WHERE generated_from IS NULL;

-- 3. Внасяме loyality_points → obshti_kodove
INSERT INTO obshti_kodove
  (ot_kade, generated_from, kod, sait,
   data_sazdaden, data_validen, data_izpolzvan,
   izpolzvan_pati, max_uses, tip, value, komentar, potrebitel)
SELECT
   COALESCE(ot_kade,'the-marketer'),
   'the-marketer',
   kod, sait,
   data_sazdaden, data_validen, data_izpolzvan,
   CASE izpolzvan WHEN '1' THEN 1 ELSE 0 END,   -- counter
   1,                                            -- single-use
   tip, value, komentar, potrebitel
FROM loyality_points
WHERE kod IS NOT NULL AND kod <> ''
ON DUPLICATE KEY UPDATE id = obshti_kodove.id;   -- skip ако кодът вече съществува (защита срещу UNIQUE clash)
```

## PHP промени

**`public_html/citte/the-marketer/promo-codes.php:46`** — INSERT-ва в `obshti_kodove` с `generated_from='the-marketer'` и `max_uses=1`:

```php
$queryPromoCode = "INSERT INTO obshti_kodove
  (ot_kade, generated_from, kod, sait, data_sazdaden, data_validen, izpolzvan_pati, max_uses, tip, value)
  VALUES ('the-marketer', 'the-marketer', $codeForQuery, $site, $createdAt, $expiration, 0, 1, $type, $value)";
```

API response остава непроменен — The Marketer не вижда промяната.

## Verification

```sql
-- Преди миграцията
SELECT 'loyality_points' src, COUNT(*) cnt FROM loyality_points
UNION ALL SELECT 'obshti_kodove', COUNT(*) FROM obshti_kodove;

-- След миграцията
SELECT generated_from, COUNT(*) FROM obshti_kodove GROUP BY generated_from;
-- очаквано: manual = старите obshti; the-marketer = старите loyality (минус duplicates)
```

Когато всичко е стабилно (≥1-2 седмици в production) → `DROP TABLE loyality_points`.

## Открит въпрос за Phase 1

`loyality_points.ot_kade` обикновено е `'the-marketer'`, но в `obshti_kodove` `ot_kade` е свободен текст (имена като `'ivo'`, `'ЦГ2'`). Запазвам `ot_kade` като free-form поле + добавям `generated_from` като структурираното. Двете не са дублиращи се — `ot_kade` е аудит ("кой го е добавил"), `generated_from` е канал ("откъде идва технически").

---

# Phase 2: анализ — еволюция към `promo_codes` shape

След Phase 1 имаме **една** таблица `obshti_kodove` (стара структура). Сега я сравняваме с `promo_codes` и виждаме какво трябва да се промени.

## Mapping field-по-field

| `obshti_kodove` (след merge) | `promo_codes` | Действие |
|---|---|---|
| `id` | `id` | ✅ без промяна |
| `kod` VARCHAR(255) | `code` VARCHAR(50) | RENAME + SHRINK (проверка дали има по-дълги от 50) |
| `tip` SMALLINT (0/1/2) | `type` ENUM('percent','fixed','shipping') | TRANSFORM: `CASE tip WHEN 0 THEN 'fixed' WHEN 1 THEN 'percent' WHEN 2 THEN 'shipping' END` |
| `value` FLOAT | `discount_value` DECIMAL(10,2) | RENAME + TYPE CHANGE (float → decimal за точност) |
| `data_validen` VARCHAR(14) YYYYMMDDHHmmss | `expiration_date` DATE | TRANSFORM: `STR_TO_DATE(LEFT(data_validen,8), '%Y%m%d')` |
| `data_sazdaden` VARCHAR(14) | (липсва) или `created_at` TIMESTAMP | OPTIONAL: запазваме като `created_at` ако ни трябва аудит |
| `data_izpolzvan` VARCHAR | (липсва — derived) | DROP: `MAX(order_promo_codes.created_at) WHERE promo_code_id = X` |
| `izpolzvan_pati` INT | (липсва — derived) | DROP: `COUNT(*) FROM order_promo_codes WHERE promo_code_id = X` |
| `max_uses` INT | `max_uses` INT | ✅ директна същата семантика |
| `generated_from` ENUM | (липсва, ще добавим) | RENAME → `source`, и разширим ENUM с `'bulk-import'` |
| `ot_kade` VARCHAR | (липсва) | OPTIONAL: запазваме като `created_by_label` (audit) или drop |
| `komentar` VARCHAR | (липсва, ще добавим) | RENAME → `note` |
| `sait` VARCHAR | (липсва) | OPEN: ако ще има multi-site → добавяме `site`; иначе drop |
| `potrebitel` INT | (липсва) | OPEN: какво всъщност означава? (виж по-долу) |

## Колони, които `promo_codes` има, а `obshti_kodove` няма

Тези **се добавят чисто нови** при еволюцията:

| Нова колона | Семантика | Default при миграция от obshti_kodove |
|---|---|---|
| `remaining_amount` DECIMAL(10,2) NULL | бюджет на ваучер (само за fixed) | `NULL` (старите codes не са имали budget tracking; ако искаме — `value` за fixed) |
| `min_subtotal` DECIMAL(10,2) | минимум за приложимост | `0` (без ограничение) |
| `shipping_cap` DECIMAL(10,2) NULL | таван за shipping codes | `NULL` (без cap = безплатна доставка) |
| `max_uses_per_user` INT | лимит на потребител | `0` (безлимит) |
| `active` BOOLEAN | вкл/изкл флаг | `IF(data_validen > NOW(), 1, 0)` или `1` за всички |
| `stack_group` TINYINT NULL | stacking правила | `NULL` (комбинира се с всичко) |

## Миграция от `obshti_kodove` (post-Phase-1) към `promo_codes`

```sql
INSERT IGNORE INTO promo_codes
  (code, type, discount_value, expiration_date, max_uses, active, source, note,
   remaining_amount, min_subtotal, shipping_cap, max_uses_per_user, stack_group)
SELECT
   kod,
   CASE tip WHEN 0 THEN 'fixed' WHEN 1 THEN 'percent' WHEN 2 THEN 'shipping' END,
   CAST(value AS DECIMAL(10,2)),
   STR_TO_DATE(LEFT(data_validen,8), '%Y%m%d'),
   max_uses,
   IF(data_validen > DATE_FORMAT(NOW(),'%Y%m%d%H%i%s'), 1, 0),
   generated_from,
   komentar,
   NULL,    -- remaining_amount
   0,       -- min_subtotal
   NULL,    -- shipping_cap
   0,       -- max_uses_per_user
   NULL     -- stack_group
FROM obshti_kodove
WHERE kod IS NOT NULL AND kod <> '';
```

`INSERT IGNORE` защитава от UNIQUE clash върху `code`.

Забележка: `promo_codes` в момента няма `source` и `note` колони — те ще се добавят отделно с `ALTER TABLE promo_codes` преди тази миграция (детайли в `promo-codes-consolidation-analysis.md`).

## Какво НЕ се пренася (и защо)

- **`izpolzvan_pati`** — заместен от `COUNT(*) FROM order_promo_codes`. Историческият брояч **се губи**, освен ако решим да го запазим в нова `legacy_usage_count` колона. Препоръка: губим го (старите употреби нямат attached `order_id`, така че и без това няма как да ги rehydrate-нем коректно).
- **`data_izpolzvan`** — заместен от `MAX(order_promo_codes.created_at)`. Същата дилема — губим историята.
- **`data_sazdaden`** — ако ни трябва, добавяме `created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP` в `promo_codes` и backfill-ваме от `STR_TO_DATE(data_sazdaden,'%Y%m%d%H%i%s')`.
- **`potrebitel`** — отворен въпрос (виж по-долу).
- **`sait`** — отворен въпрос за multi-site.
- **`ot_kade`** — губим free-form audit поле; ако ни трябва, запазваме като `note` prefix или нова `created_by_label` колона.

## PHP impact след Phase 2

1. **`promo-codes.php` (API за The Marketer)** — отново го пренасочваме. От `obshti_kodove` (Phase 1 destination) → `promo_codes` (Phase 2 destination).
2. **`PromoCode.php`** — без промени (вече работи срещу `promo_codes`).
3. **Admin/backoffice** — ако има инструменти за управление на промо кодове, които пишат в `obshti_kodove`, те трябва да се пренасочат към `promo_codes`. **Този код не съществува в текущия branch** (потвърдено с grep), така че няма какво да чупим в emart кода. Ако обаче има отделен admin repo, той трябва да се провери отделно.

## Отворени въпроси (преди Phase 2)

1. **`potrebitel` колоната** — нула или число (`2`, `5`). Какво означава? Възможни интерпретации:
   - `klienti_id` на потребителя, който има право да ползва кода → нова `restricted_to_user_id` колона в `promo_codes`.
   - `klienti_id` на admin-а, който е създал кода → нова `created_by` колона.
   - Нещо съвсем друго.

   Това трябва да се изясни с някой, който знае историята на полето.

2. **`sait`** — реален ли е multi-site сценарият? Текущата `promo_codes` няма scope по сайт.

3. **Дължина на `kod`** — текущата `obshti_kodove` е VARCHAR(255), новата `promo_codes` е VARCHAR(50). Проверка:
   ```sql
   SELECT MAX(LENGTH(kod)) FROM obshti_kodove;
   SELECT MAX(LENGTH(kod)) FROM loyality_points;
   ```
   Ако има по-дълги от 50 — или ги отрязваме (rare), или вдигаме `promo_codes.code` лимита.

4. **The Marketer `expiration` формат** — `promo_codes.expiration_date` е `DATE` (само ден), а текущият код подава `YYYYMMDDHHmmss`. Губим часа — приемливо? Или вдигаме до `DATETIME`?

5. **Backfill на `order_promo_codes`** — да синтетизираме ли исторически записи за вече използваните стари codes (така че `izpolzvan_pati` counter-ите да са възстановими), или приемаме че историята започва от 0 след миграцията?

---

# Reality check — нужен ли е Phase 1 изобщо?

Phase 1 има стойност когато:
- Искаш да decommission-неш `loyality_points` бързо (защото е dead-end target за писане), без да чакаш пълната `promo_codes` migration.
- Имаш external systems, които ползват `obshti_kodove` (admin tools, reporting) и не могат веднага да се преточат към `promo_codes`.

Phase 1 НЯМА смисъл ако:
- Можеш да преходиш и двете таблици директно към `promo_codes` за един спринт.
- Няма external readers на `obshti_kodove` (което grep-ът в emart кода потвърждава).

В нашия случай grep-ът не намери четения на `obshti_kodove` в emart PHP — но не съм проверил admin репозитории, бази с stored procs, или други системи. Ако те съществуват и също нямат readers → Phase 1 е излишен. Ако имат → Phase 1 е удобен междинен compatibility step.

---

# Свързани файлове

- `public_html/citte/the-marketer/promo-codes.php` — API за генериране (трябва промяна в Phase 1, после в Phase 2).
- `public_html/citte/lib/PromoCode.php` — нова логика, цели `promo_codes` (без промени).
- `public_html/citte/api/promo-validate.php`, `promo-cart.php` — AJAX endpoints (без промени).
- `public_html/citte/api/promo-validate-table.sql` — DDL за `promo_codes` + sister tables.
- `mysql-dumps/promo-codes-docs.md` — пълна документация на новата система.
- `mysql-dumps/imartap.sql:29845` — `loyality_points` schema.
- `mysql-dumps/imartap.sql:46091` — `obshti_kodove` schema.
- `mysql-dumps/imartap.sql:541501` — коментар на `porachki.promo_kod`, обяснява историческото намерение.
- `promo-codes-consolidation-analysis.md` — предходен анализ за консолидиране (по-обширен, включва и `source`/`site`/`note` ALTER на `promo_codes`).
