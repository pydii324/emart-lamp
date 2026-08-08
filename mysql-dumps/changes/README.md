# Промени по промо схемата — 37 региона, 18 валути, EUR база

ALTER-скриптове, които водят **вече мигрирана** промо база от старата схема до
тази, която текущата версия на storefront PHP пише и чете.

Това **не е** миграция от нула. Ако базата няма нищо промо-related, това е грешната
папка — виж `../promo_codes/fresh/`.

| | От (baseline) | До (край) |
|---|---|---|
| `promo_codes.site` | `VARCHAR(10)` или `ENUM('bg','ro','gr','al')` | `ENUM(37 региона) NULL` |
| `promo_codes.currency` | `ENUM('BGN','EUR','ALL','RON') DEFAULT 'BGN'` | `ENUM(18 валути) DEFAULT 'EUR'` |
| `cart_promo_codes.currency` | същите 4 | същите 18 |
| `order_promo_codes.currency` | същите 4 | същите 18 |
| `currency_rates` | `rate_to_bgn`, база BGN, 4 реда | `rate_to_eur`, база EUR, 18 реда |

Списъкът с региони трябва да е байт-идентичен с `PromoCode::SITES`
(`public_html/citte/lib/PromoCode.php`), а валутите — с `PromoCode::SITE_CURRENCY`.

Пълна документация на системата: `public_html/citte/docs/promo-codes-system.md`.

## Философия: fail-fast, не идемпотентност

- **Гол SQL. Нула guards.** Няма `IF NOT EXISTS`, няма `information_schema`
  проверки, няма `PREPARE`/`EXECUTE`, няма `INSERT IGNORE`.
- **Не е идемпотентно — нарочно.** Файловете се пускат ръчно. Ако нещо вече го има,
  MySQL връща грешка и спира — това е **сигналът**, а не шум. Повторно пускане на
  `01` **трябва** да върне `ERROR 1054 ... Unknown column 'rate_to_bgn'`; на `02` →
  `ERROR 1062 ... Duplicate entry`.
- **Изключение — `03`–`06`.** `UPDATE` (03) и `MODIFY COLUMN` (04/05/06) по природа
  не гърмят при повторно пускане: 03 просто хваща 0 реда, а 04/05/06 предекларират
  същия тип. За тях сигналът за състояние е `00-preflight`, не грешка.
- **Без `USE`.** Избираш базата при пускане: `mysql -D <db> < файл.sql`.
- **Прекъсването е половинчато.** Гол SQL спира по средата на файла и оставя
  предходните statement-и приложени. Затова `00-preflight.sql` съществува — пуска се
  ПРЕДИ всичко останало и доказва, че базата наистина е на очаквания baseline.

## Run-матрица

| # | Файл | imartap | Регионална | Обект |
|---|---|:---:|:---:|---|
| 00 | `00-preflight.sql` | ✅ | ✅ | **Read-only.** Доказва baseline-а: `rate_to_bgn`, 4-валутните ENUM-и, кои редове ще бъдат паркирани |
| 01 | `01-rebase-currency-rates-to-eur.sql` | ✅ | — | `rate_to_bgn` → `rate_to_eur`, всяка стойност ÷ 1.95583, EUR=1.0 / BGN=0.51129188 fixed |
| 02 | `02-seed-new-currency-rates.sql` | ✅ | — | 14 нови реда в `currency_rates` (CZK…CAD) |
| 03 | `03-park-unconvertible-sites.sql` | ✅ | — | Паркира `site` стойности извън 37-те региона на `NULL` (старата стойност → `note`, `active` = 0) |
| 04 | `04-extend-promo_codes-enums.sql` | ✅ | — | `promo_codes`: `site` → 37, `currency` → 18 |
| 05 | `05-extend-order_promo_codes-currency.sql` | ✅ | ✅ | `order_promo_codes.currency` → 18 |
| 06 | `06-extend-cart_promo_codes-currency.sql` | — | ✅ | `cart_promo_codes.currency` → 18 |
| 07 | `07-verify.sql` | ✅ | ✅ | **Read-only.** Доказва какво реално е кацнало |

## Ред на пускане

```
imartap:      00 → 01 → 02 → 03 → 04 → 05 → 07
Регионална:   00 → 05 → 06 → 07          (по веднъж за всеки регион)
```

Задължителни зависимости:

- **01 преди 02** — 02 пише `rate_to_eur`; върху таблица с `rate_to_bgn` гърми с
  `ERROR 1054`. Стойностите в 02 са EUR-базирани — в левова таблица биха били
  сгрешени с фактор 1.95583.
- **03 преди 04** — 04 стеснява `site` до ENUM с 37 стойности. Стойност, която ENUM-ът
  няма, се реже до `''` (или гърми под STRICT). 03 я премества на `NULL`, докато
  колоната още я побира. Ако редът се обърне → `07` check C го хваща, но данните вече
  са загубени.
- **01 преди PHP-то да тръгне** — `PromoCode::toEur()` чете `rate_to_eur`.

Между 05 и 06 няма зависимост — редът им на регионалната е удобен, не задължителен.

## Пускане

**По един файл, ръчно, и четеш изхода на всеки.** Без цикли, без `--force` — целта е
да спре при първата грешка.

```bash
DB=imartap                # или <regional_db>
CT=<mysql-container>

# 0) Pre-flight — всеки ред трябва да е OK или ALREADY DONE. FAIL = спри.
docker exec -i "$CT" mysql -u root -p<pass> -D "$DB" --table --force < 00-preflight.sql

# 1..N) Миграциите — по една, с проверка на exit code
docker exec -i "$CT" mysql -u root -p<pass> -D "$DB" < 01-rebase-currency-rates-to-eur.sql; echo "exit=$?"
docker exec -i "$CT" mysql -u root -p<pass> -D "$DB" < 02-seed-new-currency-rates.sql;      echo "exit=$?"
# … и така нататък по реда горе

# Накрая) Верификация
docker exec -i "$CT" mysql -u root -p<pass> -D "$DB" --table --force < 07-verify.sql
```

`--force` е **само** за `00` и `07` (read-only; продължава покрай очакваните
`ERROR 1146` за таблица, която не съществува на този target). **Никога** на `01`–`06`
— там спрелият run е целият смисъл.

> **Charset при `04`:** `site` COMMENT-ът е на кирилица. Файлът сам прави
> `SET NAMES utf8mb4;`, но ако cli-ят ти форсира друго — добави
> `--default-character-set=utf8mb4`, иначе коментарът в схемата става mojibake.

## ⚠ Какво този set НЕ прави

**Ре-базирането не конвертира записаните суми.** `01` пипа само таблицата с курсове.
Голите парични колони, писани докато количката беше в лева, нямат собствена валута:

- `cart_promo_codes.discount_value`
- `order_promo_codes.discount_applied`
- `porachki.pordost_coupon_discount` / `porachki_l|_no.promo_fixed_discount`

Стара поръчка, прочетена след смяната, излиза **1.95583× по-голяма**. Редовете в
`promo_codes` са наред — те носят своята `currency`, така че `toEur()` ги конвертира
правилно (код за 19.56 BGN приспада точно 10.00 EUR).

Конвертирането на голите колони е отделна data миграция със свой cut-over въпрос
(кои поръчки предхождат смяната?). Замрази промо записите по време на смяната, за да
има чиста граница.

**Не се пипат** и: `subtype`, `shipping_percent` типът, FK-ите на imartap
`order_promo_codes`, промо колоните по `item*` / `porachki*`, промо SKU-тата в
`catalog`. Те се приемат за налични — това е baseline-ът.

## Ако базата НЕ е на очаквания baseline

`00-preflight` връща `FAIL` при неочаквана форма. Какво означава:

| Симптом | Значение | Какво да пуснеш |
|---|---|---|
| Check B показва `rate_to_eur` | 01 вече е минал | Прескочи 01 |
| Check C/D показват 37/18 | 04/05/06 вече са минали за тази таблица | Прескочи ги |
| Check D показва ширина ≠ 4 и ≠ 18 | Междинно състояние | Ръчно; сравни с `../promo_codes/fresh/` |
| Няма `currency` колона изобщо | Инстанцията е отпреди `deploy/02` | `../deploy/02` → `../deploy/07`, после насам |
| Няма `currency_rates` таблица | Инстанцията е отпреди `deploy/06` | `../deploy/06`, после насам |
| Check F показва UNIQUE само по `code` | Независим от този set | `../deploy/09-fix-promo-codes-code-site-unique.sql` |
| `item*` имат `it_cena` като `VIRTUAL GENERATED` | Базата е минала по стария path | `../deploy/01` → `../deploy/05` първо |

Check E (`WARN — order drifted`) не е блокер: конверсията остава коректна по стойност,
просто струва пълно пренаписване на таблицата и разваля сравнението на `COLUMN_TYPE`.

## Ако нещо гръмне по средата

Гол SQL спира на statement-а, който е гръмнал, и **оставя предходните приложени**.
`01` например прави 4 statement-а — ако третият гръмне, първите два са минали.

1. Прочети грешката — казва точно кой обект е проблемният.
2. Пусни `07-verify.sql`, за да видиш какво реално е кацнало.
3. Довърши липсващото ръчно.

Най-честите:

| Грешка | Значение |
|---|---|
| `ERROR 1054 ... Unknown column 'rate_to_bgn'` | 01 вече е минал — прескочи го |
| `ERROR 1054 ... Unknown column 'rate_to_eur'` | Пускаш 02 преди 01 |
| `ERROR 1062 ... Duplicate entry` | 02 вече е минал, или някоя от 14-те валути вече има ред (`00` check I го показва) |
| `ERROR 1146 ... Table 'X' doesn't exist` | Грешен target — напр. 06 срещу imartap, или 01–04 срещу регионална |
| `ERROR 1265 ... Data truncated for column 'site'` | Пускаш 04 без 03. Под STRICT mode (`STRICT_TRANS_TABLES` — dev го има) ALTER-ът се отхвърля изцяло и нищо не се губи: пусни 03 и повтори 04. **Без** STRICT няма грешка — стойността тихо става `''` и `07` check C я хваща post-factum |

## Rollback

Пълен rollback няма — `03` унищожава старите `site` стойности (запазени са само като
текст в `note`). Схемните промени са обратими:

```sql
-- imartap
ALTER TABLE `promo_codes`
  MODIFY `currency` ENUM('BGN','EUR','ALL','RON') NOT NULL DEFAULT 'BGN',
  MODIFY `site`     ENUM('bg','ro','gr','al') NOT NULL;
ALTER TABLE `order_promo_codes`
  MODIFY `currency` ENUM('BGN','EUR','ALL','RON') NOT NULL DEFAULT 'BGN';
DELETE FROM `currency_rates`
 WHERE `currency` IN ('CZK','DKK','GBP','HUF','MDL','MKD','PLN','RSD',
                      'RUB','SEK','TRY','UAH','USD','CAD');
UPDATE `currency_rates` SET `rate_to_eur` = ROUND(`rate_to_eur` * 1.95583, 8);
UPDATE `currency_rates` SET `rate_to_eur` = 1.00000000 WHERE `currency` = 'BGN';
UPDATE `currency_rates` SET `rate_to_eur` = 1.95583000 WHERE `currency` = 'EUR';
ALTER TABLE `currency_rates`
  CHANGE `rate_to_eur` `rate_to_bgn` DECIMAL(18,8) NOT NULL
    COMMENT '1 unit of `currency` = rate_to_bgn BGN';
```

```sql
-- всяка регионална
ALTER TABLE `cart_promo_codes`
  MODIFY `currency` ENUM('BGN','EUR','ALL','RON') NOT NULL DEFAULT 'BGN';
ALTER TABLE `order_promo_codes`
  MODIFY `currency` ENUM('BGN','EUR','ALL','RON') NOT NULL DEFAULT 'BGN';
```

**Стесняването на ENUM-а е деструктивно**: всеки ред, чиято стойност вече не е в
списъка (код в PLN, регион `de`), се реже до `''`. Провери преди това:

```sql
SELECT `site`, `currency`, COUNT(*) FROM `promo_codes`
WHERE `site` NOT IN ('bg','ro','gr','al')
   OR `currency` NOT IN ('BGN','EUR','ALL','RON')
GROUP BY `site`, `currency`;
```

`MODIFY site ... NOT NULL` също гърми, ако `03` е паркирал редове на `NULL` — първо
им дай реален регион или ги изтрий.

## Бележки

- **ENUM-ите се разширяват само в края.** `bg,ro,gr,al` и `BGN,EUR,ALL,RON` пазят
  първите си четири позиции. Причината е **цена, не корупция**: MySQL конвертира ENUM
  по низа на стойността, така че вмъкване по средата не разваля данни, но налага
  `ALGORITHM=COPY` (пълно пренаписване на таблицата) вместо in-place промяна, и чупи
  сравнението на `COLUMN_TYPE`, на което стъпва `07-verify.sql`.
- **`site` става NULLable тук, но е `NOT NULL` във `fresh/06`.** И двете форми са
  правилни: `fresh/06` цели девствена база без legacy редове, а тук `03` трябва къде
  да паркира неконвертируемите стойности. `NULL` не матчва никой регион — `siteSql()`
  ползва `IN`, което никога не хваща `NULL`.
- **`'co'` = Канада (CAD)**, не .co TLD и не Колумбия. `'en'`/`'biz'`/`'org'` са
  storefront-и, не държави — нямат национална валута и са мапнати към EUR.
- **`'al'` = Албания е истински регион.** Пенсионираният wildcard `'all'` е на една
  буква разстояние — не ги бъркай. `03` паркира `'all'` редовете.
- **BGN не изчезва.** Никой регион не пише в него (`SITE_CURRENCY['bg']` е `'EUR'` —
  България е само евро), но стойността в ENUM-а и редът в `currency_rates` остават,
  защото старите BGN кодове и всички минали поръчки още ги сочат.
- **Нов регион = три промени, в този ред:** ENUM-ът на `site` → `PromoCode::SITES` →
  `PromoCode::SITE_CURRENCY`. Без валута the-marketer генераторът връща 500 за региона,
  дори SITES да го приема за осребряване. Валутата трябва да е и в `currency` ENUM-а на
  трите таблици, и като ред в `currency_rates` — иначе `toEur()` пада на курс `1.0`.
- **Курсовете в `02` са placeholder-и**, не котировки. `source = 'bnb'` редовете се
  презаписват при първия run на `scripts/update-currency-rates.php`;
  `source = 'manual'` (ALL/MDL/MKD/RSD) — никога, и трябва да се сложат ръчно преди
  да се авторира код в тях.
