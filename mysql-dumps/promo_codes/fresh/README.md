# Промо кодове — миграции за среда от нула

Единственият набор миграции за промо кодовете. Води база от **оригиналното
pre-migration състояние** (жива регионална / imartap **преди** каквато и да е
промо/цена миграция) до схемата, която текущата версия на storefront PHP пише и чете.

Замества старите `new/` + `old/` пътища (46 исторически стъпки, изтрити 2026-08-02).
Голяма част от тях бяха междинни и се самоанулираха — `it_cena_baza` →
virtualize → rename → destore → drop. Нетният им ефект върху нова база беше нула.
Тук е само крайният, additive резултат.

**Обхватът включва и imartap** (не само регионалната) — албанската регионална и живата
imartap не са изравнени, този set покрива и двете.

Пълна документация на системата: `public_html/citte/docs/promo-codes-system.md`.

## Философия: fail-fast, не идемпотентност

- **Гол SQL. Нула guards.** Няма `IF NOT EXISTS`, няма `information_schema` проверки,
  няма `PREPARE`/`EXECUTE`, няма `INSERT ... WHERE NOT EXISTS`, няма `INSERT IGNORE`.
- **Не е идемпотентно — нарочно.** Файловете се пускат ръчно. Ако нещо вече го има,
  MySQL връща грешка и спира — това е **сигналът**, а не шум. Guard-нат файл би
  премълчал същата ситуация като „no-op" и би те оставил да мислиш, че всичко е минало.
  Повторно пускане на `01` **трябва** да върне `ERROR 1050 ... Table
  'cart_promo_codes' already exists`; на `03` → `ERROR 1060 ... Duplicate column name
  'discount_applied'`.
- **Чисто additive — стейтът на базата остава непокътнат.** Само `CREATE TABLE`,
  `ALTER TABLE ... ADD COLUMN` и `INSERT`. Нула `DROP`, нула `CHANGE`, нула `UPDATE`
  върху съществуващи редове. Единственият `DROP` в целия документ е в §Reset накрая
  и е ръчна операция.
- **Приема оригиналните `it_cena` / `it_suma`** (stored FLOAT) за дадени — така беше
  преди миграциите. Не преименува и не виртуализира нищо.
- **Без `USE`.** Избираш базата при пускане: `mysql -D <db> < файл.sql`.
- **Без data-backfill** (loyality_points / obshti_kodove) — BG legacy, неприложимо.
- **Прекъсването е половинчато.** Гол SQL спира по средата на файла и оставя
  предходните statement-и приложени. Затова `00-preflight.sql` съществува — пуска се
  ПРЕДИ всичко останало и доказва, че средата наистина е празна.

## Run-матрица

| # | Файл | Регионална (AL) | imartap | Обект |
|---|---|:---:|:---:|---|
| 00 | `00-preflight.sql` | ✅ | ✅ | **Read-only.** Доказва, че средата е от нула — липсват промо таблиците, `item*` имат оригиналните stored `it_cena`/`it_suma`, няма `it_cena_baza`/`it_cena_suma`, няма промо колони, няма seed-нати SKU-та |
| 01 | `01-create-cart_promo_codes.sql` | ✅ | — | `cart_promo_codes` (cart pivot, без cross-DB FK; currency/subtype/discount_value/shipping_percent вътре) |
| 02 | `02-create-order_promo_codes.sql` | ✅ | — | `order_promo_codes` (регионална половина, **без** FK) |
| 03 | `03-add-item-promo-columns.sql` | ✅ | ✅ | `item`/`item_l`/`item_no`: `discount_applied`, `it_cena_new`, `it_suma_new`, `item_br_new`, `promot_new` |
| 04 | `04-add-porachki-promo-columns.sql` | ✅ | ✅ | `pordost_coupon_discount` (porachki/`_l`/`_no`) + `promo_fixed_discount` (`_l`/`_no`) |
| 05 | `05-seed-catalog-promo-skus.sql` | ✅ | — | Промо SKU редове в `catalog` (5555555/6666666/7777777/8888888; cena=0, vidimost=0, p_acti=0) |
| 06 | `06-create-imartap-promo_codes.sql` | — | ✅ | `promo_codes` (каталог / дефиниция — id master, споделен между всички региони) |
| 07 | `07-create-imartap-order_promo_codes.sql` | — | ✅ | `order_promo_codes` (imartap копие) **с** FK → `porachki.porachki_id` + `promo_codes.id` |
| 08 | `08-seed-imartap-promo_codes.sql` | — | ✅ | `promo_codes` seed: по 1 example ред на тип (percent / fixed voucher / fixed coupon / shipping full / shipping capped / shipping_percent / lek voucher) |
| 09 | `09-create-imartap-currency_rates.sql` | — | ✅ | `currency_rates` + 17 реда (BGN/EUR fixed; RON и 12 други от BNB; ALL/MDL/MKD/RSD ръчни) |
| 10 | `10-verify.sql` | ✅ | ✅ | **Read-only.** Доказва какво реално е кацнало |

**Защо 03/04 вървят и на двете:** `item` и `porachki` master-ите живеят в imartap, а
регионалната държи `_l`/`_no` cart копията + item/porachki реплика. Промо колоните трябват
навсякъде, където PHP-то пише/чете тези таблици.

**Защо `order_promo_codes` е на две места:** `PromoCode::finalize()` пише imartap ПЪРВО
(autoincrement master), чете id-то, после го огледава в регионалната
(`lib/PromoCode.php:304-333`). Разликата регионална↔imartap = само FK-ите (реални само в
imartap, защото и двата master-а — `porachki`, `promo_codes` — са там). `cart_promo_codes`
обратно — **само** регионална, никога imartap.

## Ред на пускане

```
Регионална (AL):   00 → 01 → 02 → 03 → 04 → 05 → 10
imartap:           00 → 03 → 04 → 06 → 09 → 07 → 08 → 10
```

Зависимости, които правят реда на imartap задължителен:

- **06 преди 07** — FK-ът `fk_opc_promo_code_id` сочи `promo_codes.id`.
- **06 преди 08** — 08 seed-ва в `promo_codes`.
- **09 преди 08** — не е схемна зависимост, а практическа: EUR/лек кодовете от 08 се
  конвертират към BGN през `currency_rates`; ако таблицата липсва,
  `PromoCode::toBgn()` мълчаливо пада на 1.0 и seed-ът изглежда счупен при първия тест.
- `porachki` (от основната схема) трябва да съществува в imartap за 07.

Регионалната няма вътрешни зависимости — 01→05 е просто удобен ред.

## Пускане

**По един файл, ръчно, и четеш изхода на всеки.** Без цикли, без `--force` — целта е
да спре при първата грешка.

```bash
DB=<regional_db>          # или imartap
CT=<mysql-container>

# 0) Pre-flight — всеки ред трябва да е OK. FAIL някъде = базата НЕ е от нула, спри.
docker exec -i "$CT" mysql -u root -p<pass> -D "$DB" --table --force < 00-preflight.sql

# 1..N) Миграциите — по една, с проверка на exit code
docker exec -i "$CT" mysql -u root -p<pass> -D "$DB" < 01-create-cart_promo_codes.sql; echo "exit=$?"
docker exec -i "$CT" mysql -u root -p<pass> -D "$DB" < 02-create-order_promo_codes.sql; echo "exit=$?"
# … и така нататък по реда горе

# Накрая) Верификация
docker exec -i "$CT" mysql -u root -p<pass> -D "$DB" --table --force < 10-verify.sql
```

`--force` е **само** за `00` и `10` (read-only; продължава покрай очакваните
`ERROR 1146` за таблица, която не съществува на този target). **Никога** на `01`–`09`
— там спрелият run е целият смисъл.

> **Charset при seed (05 и 08):** зареждай с utf8mb4, иначе кирилицата се записва
> mojibake. И двата файла сами правят `SET NAMES utf8mb4;`, но ако cli-ят ти форсира
> друго — добави `--default-character-set=utf8mb4`.

> **08 е опционален** — само example промо кодове (по 1 на тип), маркирани
> `created_by='fresh-seed'`. Прескочи го ако не искаш живи sample кодове в каталога,
> или ги изтрий след верификация:
> `DELETE FROM promo_codes WHERE created_by = 'fresh-seed';`

## Ако нещо гръмне по средата

Гол SQL спира на statement-а, който е гръмнал, и **оставя предходните приложени**.
`03` например прави три отделни `ALTER`-а (`item_l`, `item_no`, `item`) — ако третият
гръмне, първите два са минали.

1. Прочети грешката — тя ти казва точно кой обект е проблемният.
2. Пусни `10-verify.sql`, за да видиш какво реално е кацнало.
3. Или довърши липсващото ръчно, или се върни на чисто през §Reset и пусни файла отначало.

Най-честите:

| Грешка | Значение |
|---|---|
| `ERROR 1050 ... Table 'X' already exists` | Таблицата вече я има — `01`/`02`/`06`/`07`/`09` вече са минали, или базата не е от нула |
| `ERROR 1060 ... Duplicate column name 'X'` | Колоната вече я има — `03`/`04` вече са минали за тази таблица |
| `ERROR 1146 ... Table 'X' doesn't exist` | Пускаш файл срещу грешния target (напр. `01` срещу imartap, или `05` срещу база без `catalog`) |
| `ERROR 1062 ... Duplicate entry` | `08`/`09` seed вече е минал (`promo_codes` има UNIQUE KEY (`code`,`site`), `currency_rates.currency` е PK) |
| `ERROR 1215 ... Cannot add foreign key constraint` | `07` преди `06`, или `porachki` липсва в imartap |

**⚠️ Единственото изключение — `05`:** `catalog` няма UNIQUE KEY на `cat_no`, така че
повторно пускане **не гърми** — вкарва четири дублирани реда тихо. Това е единственият
файл в набора без естествена защита. Затова `00-preflight` го проверява изрично.
Ако все пак стане:

```sql
DELETE FROM `catalog` WHERE `cat_no` IN ('5555555','6666666','7777777','8888888');
-- после пусни 05 наново
```

## Ако базата НЕ е от нула

Този набор е само за среда без нищо промо-related. За вече частично мигрирана база
(dev/staging, минала по историческия път) ползвай `../../deploy/*` — там файловете са
guard-нати reconcile стъпки (rename / destore / drop / FK), точно защото трябва да са
безопасни върху наполовина мигрирана жива схема.

Разпознаване: `00-preflight.sql` check C. На оригинал `it_cena`/`it_suma` са stored
(`EXTRA` празно). Ако са `VIRTUAL GENERATED`, или ако има `it_cena_baza` /
`it_cena_suma` — базата е минала по стария път, **не** пускай този набор.

## Reset (чист старт)

Единственото място с `DROP` в целия набор. Ръчна операция — прочети я преди да я пуснеш.

```sql
-- регионална
DROP TABLE IF EXISTS cart_promo_codes, order_promo_codes;
ALTER TABLE item     DROP COLUMN discount_applied, DROP COLUMN it_cena_new, DROP COLUMN it_suma_new, DROP COLUMN item_br_new, DROP COLUMN promot_new;
ALTER TABLE item_l   DROP COLUMN discount_applied, DROP COLUMN it_cena_new, DROP COLUMN it_suma_new, DROP COLUMN item_br_new, DROP COLUMN promot_new;
ALTER TABLE item_no  DROP COLUMN discount_applied, DROP COLUMN it_cena_new, DROP COLUMN it_suma_new, DROP COLUMN item_br_new, DROP COLUMN promot_new;
ALTER TABLE porachki    DROP COLUMN pordost_coupon_discount;
ALTER TABLE porachki_l  DROP COLUMN pordost_coupon_discount, DROP COLUMN promo_fixed_discount;
ALTER TABLE porachki_no DROP COLUMN pordost_coupon_discount, DROP COLUMN promo_fixed_discount;
DELETE FROM catalog WHERE cat_no IN ('5555555','6666666','7777777','8888888');
```

```sql
-- imartap (order_promo_codes ПРЕДИ promo_codes — FK ред); item/porachki колоните — като горе
DROP TABLE IF EXISTS order_promo_codes;
DROP TABLE IF EXISTS promo_codes;
DROP TABLE IF EXISTS currency_rates;
-- само 08 seed кодовете (ако таблицата остава): DELETE FROM promo_codes WHERE created_by = 'fresh-seed';
```

След reset `00-preflight.sql` трябва отново да е OK навсякъде.

## Бележки

- **Charset.** Живата BG `catalog.ime` е корумпирана at-rest (mojibake, double-encoded с
  latin1 клиент). Файл 05 нарочно НЕ възпроизвежда бъга (`SET NAMES utf8mb4`).
- `miarka` в seed-а е `бр.` (както в BG). Смени ако Албания ползва друг етикет.
- `promo_codes.site` ENUM е с **37 региона** — **един регион на код, няма wildcard**.
  Редът е `bg,ro,gr,al` (първоначалните четири, заковани на първите четири позиции —
  ENUM пази пореден номер, не низ, така че пренареждане би преназначило всички
  съществуващи редове) и след тях `en,md,at,cz,de,es,hr,hu,it,pl,si,sk,cy,uk,us,co,be,
  dk,ee,fi,fr,lt,lv,nl,pt,se,mk,rs,ua,tr,ru,biz,org`. Списъкът трябва да е идентичен с
  `PromoCode::SITES`. `en`/`biz`/`org` са storefront-и, не държави.
  Старото `'all'` (валиден навсякъде) е пенсионирано: `lib/PromoCode.php` матчва региона
  точно, а `deploy/08-retire-site-all-wildcard.sql` деактивира останалите служебни редове.
  **`'al'` = Албания е истински регион** — една буква разлика от мъртвия wildcard.
- Инстанция, която вече е на стария ENUM с четирите региона (или още е на
  `VARCHAR(10)`), се мигрира с `mysql-dumps/deploy/10-extend-site-and-currency-enums.sql`.
  Там `site` става **NULLable** — файлът паркира неконвертируемите стойности (wildcard-а,
  печатните грешки) на `NULL`, вместо да ги загуби; `NULL` не матчва никой регион.
- Нов регион = **три** промени, в този ред: ENUM-ът тук → `PromoCode::SITES` →
  `PromoCode::SITE_CURRENCY`. Без валута the-marketer генераторът връща 500 за региона,
  дори SITES да го приема за осребряване. Валутата трябва да е и в `currency` ENUM-а на
  трите таблици, и като ред в `currency_rates` — иначе `toBgn()` пада на курс `1.0`.
- Валута/site етикет за Албания различни? — това е на imartap каталог страна, отделна задача.
