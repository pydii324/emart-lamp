# Promo codes — master план

> Този документ замества `promo-codes-consolidation-analysis.md` и `merge-and-migrate-promo-codes-plan.md`. Те остават като reference, но **този е единственият актуален план**.

## Контекст и решения

В момента имаме три промо таблици в `imartap`:
- `loyality_points` — single-use codes от The Marketer (има PHP writer, няма reader).
- `obshti_kodove` — multi-use ръчни codes (има данни, няма PHP usage).
- `promo_codes` (нова система) — има PHP код срещу нея (`PromoCode.php`, `promo-validate.php`, `promo-cart.php`, integration в `case.php`), но **не е активно в production** — никой реален промо код не минава през тази система.

**Решение:** Тъй като новата `promo_codes` не е production-active, имаме свобода да я **redesign-нем** преди да наляхме данните в нея. Едностъпков път: `loyality_points` + `obshti_kodove` → redesigned `promo_codes`. Без междинна "обединена в obshti_kodove" таблица.

## Design requirements (нови)

1. **`remaining_amount` → `voucher_remainer`** (по-описателно име, само за `fixed` type).
2. **Metadata колони**: `created_at`, `used_at` (last-used). Ivo ще ги иска за audit/reporting.
3. **Дати като VARCHAR(14) в `YYYYMMDDHHmmss`** формат — съответства на PHP `date('YmdHis')`. Без MySQL `DATE`/`TIMESTAMP` типове в нашите таблици. Това вече е конвенцията в `imartap` (`loyality_points.data_sazdaden`, `obshti_kodove.data_validen` и др.).

---

## Целева схема — `promo_codes`

```sql
CREATE TABLE `promo_codes` (
  `id`                INT          NOT NULL AUTO_INCREMENT,
  `code`              VARCHAR(50)  NOT NULL,
  `type`              ENUM('percent','fixed','shipping') NOT NULL DEFAULT 'percent',

  -- Стойност
  `discount_value`    DECIMAL(10,2) NOT NULL,
  `voucher_remainer`  DECIMAL(10,2) NULL DEFAULT NULL,  -- бивш remaining_amount; само за fixed (бюджет, намалява при употреба)

  -- Ограничения
  `min_subtotal`      DECIMAL(10,2) NOT NULL DEFAULT 0,
  `shipping_cap`      DECIMAL(10,2) NULL DEFAULT NULL,  -- само за shipping (NULL = без cap)
  `max_uses`          INT          NOT NULL DEFAULT 0,  -- 0 = безлимит
  `times_used`        INT          NOT NULL DEFAULT 0,  -- брояч; ++ при markUsed()

  -- Поведение
  `active`            BOOLEAN      NOT NULL DEFAULT TRUE,
  `stack_group`       TINYINT      NULL DEFAULT NULL,   -- NULL = комбинира се с всичко

  -- Дати (всички VARCHAR(14) YYYYMMDDHHmmss)
  `expiration_date`   VARCHAR(14)  NULL DEFAULT NULL,
  `created_at`        VARCHAR(14)  NOT NULL,            -- винаги се сетва при INSERT
  `used_at`           VARCHAR(14)  NULL DEFAULT NULL,   -- last-used; update-ва се при markUsed()

  -- Произход / метадата
  `source`            ENUM('the-marketer','manual','bulk-import') NOT NULL DEFAULT 'manual',
  `note`              VARCHAR(255) NULL DEFAULT NULL,   -- бивш komentar
  `site`              VARCHAR(10)  NULL DEFAULT NULL,   -- бивш sait ('bg','ro','gr','all') — OPEN: дали ни трябва
  `created_by`        VARCHAR(255) NULL DEFAULT NULL,   -- бивш ot_kade (free-form audit: 'ivo','ЦГ2',…)

  PRIMARY KEY (`id`),
  UNIQUE KEY `code` (`code`),
  KEY `idx_active_exp` (`active`, `expiration_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### Sister таблици — `cart_promo_codes` и `order_promo_codes`

Запазваме pivot pattern-а (по едно edge-row per cart/order), но `created_at` става VARCHAR(14) вместо TIMESTAMP:

```sql
CREATE TABLE `cart_promo_codes` (
  `id`               INT          NOT NULL AUTO_INCREMENT,
  `cart_id`          INT          NOT NULL,
  `cart_type`        ENUM('l','no') NOT NULL,
  `promo_code_id`    INT          NOT NULL,
  `code`             VARCHAR(50)  NOT NULL,
  `discount_applied` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `type`             ENUM('percent','fixed','shipping') NOT NULL,
  `shipping_cap`     DECIMAL(10,2) NULL DEFAULT NULL,
  `created_at`       VARCHAR(14)  NOT NULL,             -- бивш TIMESTAMP
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_cart_promo` (`cart_id`,`cart_type`,`promo_code_id`),
  CONSTRAINT `fk_cpc_promo` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `order_promo_codes` (
  `id`               INT          NOT NULL AUTO_INCREMENT,
  `order_id`         INT          NOT NULL,             -- porachki.porachki_id
  `promo_code_id`    INT          NOT NULL,
  `klienti_id`       INT          NOT NULL DEFAULT 0,   -- 0 = гост
  `discount_applied` DECIMAL(10,2) NOT NULL,
  `created_at`       VARCHAR(14)  NOT NULL,             -- кога е redeem-нат
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_order_promo` (`order_id`,`promo_code_id`),
  CONSTRAINT `fk_opc_promo` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### Field-by-field mapping от старите таблици

| Стара колона | Стара таблица | Нова колона в `promo_codes` | Трансформация |
|---|---|---|---|
| `kod` | и двете | `code` | директно (verify max length ≤ 50) |
| `tip` | и двете | `type` | `CASE tip WHEN 0 THEN 'fixed' WHEN 1 THEN 'percent' WHEN 2 THEN 'shipping' ELSE 'percent' END` |
| `value` | и двете | `discount_value` | `CAST(value AS DECIMAL(10,2))` |
| `data_validen` | и двете | `expiration_date` | директно (вече е YYYYMMDDHHmmss) |
| `data_sazdaden` | и двете | `created_at` | директно |
| `data_izpolzvan` | loyality_points | `used_at` | директно |
| `izpolzvan` (0/1) | loyality_points | (логика на `active`) | `IF(izpolzvan='1', 0, 1)` — usable = active |
| `izpolzvan_pati` | obshti_kodove | (губи се; брояч идва от `COUNT(order_promo_codes)`) | не се пренася |
| `ot_kade` | и двете | `created_by` (free-form) | директно |
| `komentar` | и двете | `note` | директно |
| `sait` | и двете | `site` | директно (ако пазим колоната) |
| `potrebitel` | и двете | OPEN — виж секция "Отворени въпроси" | TBD |
| (нов) `max_uses` | derived | `max_uses` | `1` за loyality (single-use), `0` за obshti (multi-use) |
| (нов) `source` | derived | `source` | `'the-marketer'` за loyality, `'manual'` за obshti |
| (нов) `voucher_remainer` | derived | `voucher_remainer` | за `tip=0` (fixed): `value`; иначе `NULL` |

---

## Migration SQL

Изпълнява се **в `imartap`**. Един transaction за двете INSERT-ове + последващи DROP-ове.

```sql
USE imartap;

START TRANSACTION;

-- Step 1: loyality_points → promo_codes (single-use, the-marketer)
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
   1,                                              -- single-use
   IF(izpolzvan = '1', 0, 1),                      -- ако вече използван → не активен
   data_validen,
   data_sazdaden,
   data_izpolzvan,
   'the-marketer',
   komentar,
   sait,
   COALESCE(NULLIF(ot_kade, ''), 'the-marketer')
FROM loyality_points
WHERE kod IS NOT NULL AND kod <> ''
  AND tip IN (0, 1, 2);                            -- филтрираме NULL/невалидни tip

-- Step 2: obshti_kodove → promo_codes (multi-use, manual)
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
   0,                                              -- multi-use (безлимит)
   IF(data_validen IS NOT NULL AND data_validen > DATE_FORMAT(NOW(),'%Y%m%d%H%i%s'), 1, 0),  -- expired → inactive
   data_validen,
   data_sazdaden,
   NULL,                                           -- obshti няма last-used timestamp
   'manual',
   komentar,
   sait,
   NULLIF(ot_kade, '')
FROM obshti_kodove
WHERE kod IS NOT NULL AND kod <> ''
  AND tip IN (0, 1, 2);

COMMIT;
```

`INSERT IGNORE` защитава от UNIQUE clash върху `code` (рядко вероятен, но трябва да се провери — виж pre-flight checks).

---

## PHP промени

### `public_html/citte/the-marketer/promo-codes.php` — rewrite на INSERT

Сегашен (`promo-codes.php:46`):
```php
$queryPromoCode = "INSERT INTO loyality_points (ot_kade, kod, sait, data_sazdaden, data_izpolzvan, data_validen, tip, value)
                   VALUES ('the-marketer', $codeForQuery, $site, $createdAt, NULL, $expiration, $type, $value)";
```

Нов — пише директно в `promo_codes`:
```php
$typeMap = [0 => 'fixed', 1 => 'percent', 2 => 'shipping'];
$typeStr = $typeMap[(int)$type] ?? 'percent';
$voucherRem = ($typeStr === 'fixed') ? (float)$value : 'NULL';
$voucherRemSql = is_string($voucherRem) ? $voucherRem : "'" . number_format($voucherRem, 2, '.', '') . "'";

$queryPromoCode = "INSERT INTO promo_codes
    (code, type, discount_value, voucher_remainer,
     max_uses, active,
     expiration_date, created_at,
     source, site, created_by)
   VALUES
    ($codeForQuery, '$typeStr', '" . number_format((float)$value, 2, '.', '') . "', $voucherRemSql,
     1, 1,
     '$expiration', '$createdAt',
     'the-marketer', $site, 'the-marketer')";
```

JSON response остава непроменен (`code`, `value`, `type` като 0/1/2, `expiration`) — The Marketer не вижда промяната.

### `public_html/citte/lib/PromoCode.php` — schema-aware промени

Файлът чете/пише `remaining_amount`. Глобален rename:

- `PromoCode.php:37-39` — SELECT-ът на `validate()`: `remaining_amount` → `voucher_remainer`.
- `PromoCode.php:98-100` — fixed-type budget check: `$r['remaining_amount']` → `$r['voucher_remainer']`.
- `PromoCode.php:120-123` — `calculateCartDiscount()` fixed branch: same rename.
- `PromoCode.php:155-178` — `getAppliedForCart()` SELECT и result mapping: rename в SQL и в return array key (consumer-ите използват `$row['remaining_amount']` като ключ — този ключ става `voucher_remainer`).
- `PromoCode.php:174` — return array key `remaining_amount` → `voucher_remainer`.
- `PromoCode.php:215` — `applyCartDiscounts()` fixed branch: `$p['remaining_amount']` → `$p['voucher_remainer']`.
- `PromoCode.php:286-292` — `markUsed()` UPDATE: rename `remaining_amount` → `voucher_remainer`. **Плюс ново**: тук вече се UPDATE-ва и `promo_codes.used_at = '$nowYmdHis'`.

Промени по датите:

- `PromoCode.php:53` — expiration check сегашна:
  ```php
  if ($r['expiration_date'] && strtotime($r['expiration_date']) < strtotime('today')) {
  ```
  Нова (string comparison, YYYYMMDDHHmmss е lexicographic-sortable):
  ```php
  if ($r['expiration_date'] && $r['expiration_date'] < date('YmdHis')) {
  ```

- `markUsed()` — добавя update на `used_at`:
  ```php
  $now = date('YmdHis');
  mysqli_query($this->db,
      "UPDATE promo_codes SET used_at = '$now'
        WHERE id = '$promoId';");
  ```

- INSERT-ите в `cart_promo_codes` и `order_promo_codes` сега трябва да включват `created_at = date('YmdHis')` (вече не е автоматичен TIMESTAMP). Викани от `persistDiscount()` (`PromoCode.php:245-254`) — но persistDiscount прави UPDATE, не INSERT. INSERT в `cart_promo_codes` се прави в `promo-cart.php`/`promo-validate.php` — там добавяме `created_at`. INSERT в `order_promo_codes` в `markUsed()` (`PromoCode.php:282-284`) — добавяме `created_at`.

### `public_html/citte/api/promo-validate.php` и `promo-cart.php`

Тези файлове правят INSERT в `cart_promo_codes`. Преглед нужен на всеки INSERT statement, който създава ред в cart_promo_codes или order_promo_codes — добавя се `created_at = date('YmdHis')` параметър.

### `public_html/citte/case.php`

Consumer на `getAppliedForCart()`. Ако някъде директно reference-ва ключа `remaining_amount` от returned array — rename. Бърза проверка:
```bash
grep -n "remaining_amount\|expiration_date" public_html/citte/case.php
```

### `public_html/citte/promo-cart-rows.php` и `promo-input.php`

UI компоненти. Възможно е да четат `voucher_remainer`/`expiration_date` за display. Преглед на reference-ите.

---

## Старите таблици — запазваме за reference

**НЕ дропваме** `loyality_points` и `obshti_kodove` след миграцията. Оставаме ги read-only като източник за сравнение и audit:

- Verification queries по време на migration и след това (counts, spot checks).
- Reference при бъдещи bug investigations — "как е изглеждал кодът преди миграцията".
- Reconciliation срещу external systems (The Marketer dashboard, admin reports).

PHP кодът трябва да **спре да пише** в тях (`promo-codes.php` API rewrite — задължителна стъпка), но самите таблици остават.

Допълнително — `porachki.promo_kod` колоната (документиран FK към старите таблици) — оставаме я също, по същите причини.

Ако в по-далечно бъдеще решим да разчистим, ще е отделна задача с explicit decision.

---

## Pre-flight checks

Преди execution на migration SQL — изпълни тези срещу dev базата:

```sql
USE imartap;

-- 1. Кодове по-дълги от 50 символа?
SELECT 'loyality_points' tbl, MAX(LENGTH(kod)) max_len, COUNT(*) total FROM loyality_points
UNION ALL
SELECT 'obshti_kodove', MAX(LENGTH(kod)), COUNT(*) FROM obshti_kodove;

-- 2. NULL или невалидни tip стойности?
SELECT 'loyality NULL/bad tip' lbl, COUNT(*) FROM loyality_points WHERE tip IS NULL OR tip NOT IN (0,1,2)
UNION ALL
SELECT 'obshti NULL/bad tip', COUNT(*) FROM obshti_kodove WHERE tip IS NULL OR tip NOT IN (0,1,2);

-- 3. Code collisions между двете таблици?
SELECT l.kod, l.id loyality_id, o.id obshti_id
FROM loyality_points l JOIN obshti_kodove o ON l.kod = o.kod;

-- 4. Невалидни (празни/NULL) кодове?
SELECT 'loyality empty kod' lbl, COUNT(*) FROM loyality_points WHERE kod IS NULL OR kod = ''
UNION ALL
SELECT 'obshti empty kod', COUNT(*) FROM obshti_kodove WHERE kod IS NULL OR kod = '';

-- 5. data_validen формат — всички ли са 14-цифров YYYYMMDDHHmmss?
SELECT 'loyality bad date' lbl, COUNT(*) FROM loyality_points
  WHERE data_validen IS NOT NULL AND (LENGTH(data_validen) <> 14 OR data_validen NOT REGEXP '^[0-9]{14}$')
UNION ALL
SELECT 'obshti bad date', COUNT(*) FROM obshti_kodove
  WHERE data_validen IS NOT NULL AND (LENGTH(data_validen) <> 14 OR data_validen NOT REGEXP '^[0-9]{14}$');

-- 6. Baseline counts
SELECT COUNT(*) loyality_total FROM loyality_points;
SELECT COUNT(*) obshti_total FROM obshti_kodove;
SELECT COUNT(*) promo_codes_before FROM promo_codes;
```

Решения според резултатите:
- Ако (1) > 50 → вдигаме `promo_codes.code` лимита.
- Ако (2) > 0 → задължително `WHERE tip IN (0,1,2)` в migration (вече е заложено).
- Ако (3) > 0 → решаваме коя версия да pre-empt-не (`INSERT IGNORE` пази the-marketer, защото е първа стъпка; ако искаме обратното — сменяме реда).
- Ако (4) > 0 → migration вече ги филтрира (`WHERE kod IS NOT NULL AND kod <> ''`).
- Ако (5) > 0 → или ги изключваме от migration, или ги нормализираме.

---

## Verification (post-migration)

```sql
-- Counts
SELECT
   (SELECT COUNT(*) FROM loyality_points)              AS loyality_count,
   (SELECT COUNT(*) FROM obshti_kodove)                AS obshti_count,
   (SELECT COUNT(*) FROM promo_codes)                  AS promo_count,
   (SELECT COUNT(*) FROM promo_codes WHERE source='the-marketer')  AS from_marketer,
   (SELECT COUNT(*) FROM promo_codes WHERE source='manual')        AS from_manual;
-- Очаквано: promo_count ≈ loyality_count + obshti_count − duplicates − invalid_tip rows

-- Spot checks — конкретни кодове
SELECT * FROM promo_codes WHERE code IN ('VELIKDEN10','slujeben10','SPRING10EM26','svet25evro','svet10procenta');

-- Type distribution
SELECT source, type, COUNT(*) FROM promo_codes GROUP BY source, type;
```

End-to-end test:
1. The Marketer API: `curl 'https://dev/themarketer/code-generator?key=...&value=10&type=1&expiration_date=2027-01-01%2009:00'` → код се появява в `promo_codes` с `source='the-marketer'`, `type='percent'`, `max_uses=1`.
2. Cart flow: прилагане на мигриран код в количка → `cart_promo_codes` ред със `created_at` YYYYMMDDHHmmss.
3. Order flow: финализиране на поръчка → `order_promo_codes` ред + `promo_codes.used_at` update.

---

## Отворени въпроси — РАЗРЕШЕНИ (2026-05-14)

> Виж `promo-codes-execution-log.md` Step 0 за пълно обяснение.

1. ~~**`potrebitel` колоната.**~~ → **DROP**. 0/18 distinct non-zero values match `klienti.klienti_id`. Никой PHP файл не я чете/пише (writer `promo-codes.php` не записва). Dead data.

2. ~~**`sait` (multi-site).**~~ → **KEEP**. Реален сценарий — `site` колоната остава в `promo_codes`.

3. ~~**The Marketer `tip` JSON.**~~ → Без промяна. API връща 0/1/2; вътрешният INSERT преобразува в ENUM.

4. ~~**Audit за исторически redeem-нати кодове.**~~ → **IGNORE**. Нямаме `order_id` за `loyality_points.izpolzvan='1'` редовете — губим audit. Без sentinel редове.

5. ~~**`data_sazdaden` за obshti_kodove.**~~ → Приемаме каквото има. Не блокира migration.

6. ~~**`active` за obshti_kodove.**~~ → **`active = IF(data_validen > date('YmdHis'), 1, 0)`**. Автоматично деактивиране на изтекли.

---

## Свързани файлове (за reference)

- `public_html/citte/the-marketer/promo-codes.php` — API за генериране (Phase 1 промяна).
- `public_html/citte/lib/PromoCode.php` — validation/redemption логика (rename + date handling).
- `public_html/citte/api/promo-validate.php`, `promo-cart.php` — AJAX endpoints (created_at INSERT).
- `public_html/citte/api/promo-validate-table.sql` — стара DDL за `promo_codes`; ще се замени с новата от този план.
- `public_html/citte/case.php`, `promo-input.php`, `promo-cart-rows.php` — consumers; grep за `remaining_amount`/`expiration_date`.
- `mysql-dumps/promo-codes-docs.md` — стара documentation; нужен update след execution.
- `mysql-dumps/imartap.sql:29845` — `loyality_points` schema.
- `mysql-dumps/imartap.sql:46091` — `obshti_kodove` schema.
- `mysql-dumps/imartap.sql:541501` — коментар на `porachki.promo_kod` (за decommission проверка).

---

## Изпълнение — стъпки в ред

1. **Pre-flight checks** (SQL queries по-горе) → решаваме отворените въпроси на тяхна база.
2. **Финализиране на схемата** (особено `site`, `potrebitel`, `created_by`).
3. **Update `mysql-dumps/promo-codes-docs.md`** с новата схема (документация-first, преди код).
4. **Подготовка на нов DDL файл** — заменя `public_html/citte/api/promo-validate-table.sql`.
5. **Execute миграцията на dev** — pre-flight → DROP стар `promo_codes` + sister tables → CREATE с новата схема → INSERT FROM old tables → verification.
6. **Update PHP кода** — `PromoCode.php` rename + date handling + `used_at` update; `promo-codes.php` API rewrite; `promo-validate.php`/`promo-cart.php` за `created_at`; case.php consumer adjustments.
7. **End-to-end testing на dev** — The Marketer API + cart + checkout flows.
8. **Production deploy** — миграция + кода едновременно (атомарен switchover).
9. **Monitor 1-2 седмици** в production. Старите таблици остават read-only за reference.
