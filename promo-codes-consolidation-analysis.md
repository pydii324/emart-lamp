# Анализ: консолидиране на промо кодовете в една таблица

## Контекст

В момента имаме три таблици, които покриват overlapping функционалност:

1. **`imartap.loyality_points`** — codes от The Marketer (външна email платформа).
2. **`imartap.obshti_kodove`** — ръчно въведени codes (Янита/Силвия).
3. **`promo_codes`** — новата нормализирана система (заедно с `cart_promo_codes` и `order_promo_codes`).

Първоначалното предложение беше: `loyality_points` → `obshti_kodove` (плюс `generated_from` enum). Анализът по-долу показва защо това не е правилният ход и какъв е по-подходящият.

## Текущо състояние

### `imartap.loyality_points`
```
id, ot_kade, kod, izpolzvan(0/1), sait, data_sazdaden, data_izpolzvan,
data_validen (varchar YYYYMMDDHHmmss), tip(0/1/2), value, komentar, potrebitel
```
- `tip`: `0`=fixed, `1`=percent, `2`=free shipping
- **PHP usage:** Записва се само от `public_html/citte/the-marketer/promo-codes.php:46` (API за The Marketer). **Никой не я чете.** Няма validation/redemption логика, която да я ползва.

### `imartap.obshti_kodove`
```
id, ot_kade, kod, sait, data_sazdaden, data_validen,
izpolzvan_pati (брояч), tip(0/1/2), value, komentar, potrebitel
```
- Същата `tip` семантика като `loyality_points`.
- **PHP usage:** Нула. Таблицата има реални данни (вкл. `VELIKDEN10`, `SPRING10EM26`, `slujeben10`), но никакъв PHP код в текущия branch не я докосва.

### `promo_codes` (новата система, документирана в `mysql-dumps/promo-codes-docs.md`)
```
id, code, type ENUM('percent','fixed','shipping'), discount_value,
remaining_amount, min_subtotal, shipping_cap, max_uses, max_uses_per_user,
active, expiration_date DATE, stack_group
```
- Плюс `cart_promo_codes` (приложени в количка) и `order_promo_codes` (използвани при поръчка).
- **PHP usage:** Активната система — `PromoCode.php`, `promo-validate.php`, `promo-cart.php`, `case.php`.

### Историческият план — `porachki.promo_kod`

Коментар в `imartap.sql:541501` на колоната `porachki.promo_kod`:
> "Промо код от таблици `obshti_kodove` & `loyality_points` (The Marketer). Чужд ключ. Може да е: % отстъпка, безплатна доставка, твърда сума."

Намерението е било единна точка за справка от orders, но не е реализирано в кода — `porachki.promo_kod` стои неизползвана.

## Сравнение feature-по-feature

| Feature | loyality_points | obshti_kodove | promo_codes (нова) |
|---|---|---|---|
| Тип код (%/fixed/shipping) | ✅ (`tip` int) | ✅ (`tip` int) | ✅ (`type` ENUM) |
| Стойност | ✅ `value` | ✅ `value` | ✅ `discount_value` |
| Срок | ✅ varchar | ✅ varchar | ✅ DATE |
| Единична употреба | ✅ `izpolzvan 0/1` | ❌ | ✅ (чрез `order_promo_codes`) |
| Брояч употреби | ❌ | ✅ `izpolzvan_pati` | ✅ (чрез `order_promo_codes` + COUNT) |
| Лимит общо | ❌ | ❌ | ✅ `max_uses` |
| Лимит на потребител | ❌ | ❌ | ✅ `max_uses_per_user` |
| Min subtotal | ❌ | ❌ | ✅ `min_subtotal` |
| Shipping cap | ❌ | ❌ | ✅ `shipping_cap` |
| Voucher budget | ❌ | ❌ | ✅ `remaining_amount` |
| Stack rules | ❌ | ❌ | ✅ `stack_group` |
| Active flag | ❌ (само срок) | ❌ | ✅ `active` |
| Multi-site (`sait`) | ✅ | ✅ | ❌ |
| Източник (`ot_kade`) | ✅ | ✅ | ❌ |
| Коментар | ✅ | ✅ | ❌ |

**Извод:** `promo_codes` е чист superset по бизнес логика. Това, което липсва, е метадатата за **произход** (`ot_kade`, `komentar`, `sait`).

## Защо merge на `loyality_points` → `obshti_kodove` НЕ е правилният ход

1. **Удвояваш работата.** Първо мигрираш `loyality_points` в `obshti_kodove`, после трябва пак да мигрираш всичко в `promo_codes`, защото новата валидация (минимум, лимити, stacking, voucher budget) изисква колоните от `promo_codes`. Иначе ще трябва или да дублираш логиката, или да forsnem `obshti_kodove` да има всички тези колони — тогава фактически правиш `promo_codes`.

2. **Имаш два различни data model-а.** `obshti_kodove.izpolzvan_pati` е agregat counter (race conditions при concurrent поръчки). Новата система ползва `order_promo_codes` pivot — counter става `COUNT(*)`, винаги точен, безопасен. Сливането обратно към counter губи това.

3. **`promo-codes.php` (API за The Marketer) пише в грешна таблица.** Сега INSERT-ва в `loyality_points`, която никой не чете. Това е dead-end. Единственото правилно действие е тя да пише в `promo_codes`.

4. **`obshti_kodove` няма читатели в PHP кода.** Сливането на още данни в нея, без читатели, не дава функционалност.

## Препоръчан подход — една таблица `promo_codes`

### 1. Добави 3 метадатни колони на `promo_codes`

```sql
ALTER TABLE promo_codes
  ADD COLUMN source ENUM('manual','the-marketer','bulk-import') NOT NULL DEFAULT 'manual',
  ADD COLUMN site VARCHAR(10) NULL DEFAULT NULL,    -- 'bg','ro','gr','all' — ако ще е multi-site
  ADD COLUMN note VARCHAR(255) NULL DEFAULT NULL;   -- бивш komentar
```

- `source` default `manual` — точно за Excel bulk import use case.
- `site` оставяме NULL-able. Може да отпадне ако решим, че няма реален multi-site сценарий (виж отворен въпрос по-долу).
- `note` за вътрешни коментари ("ЦГ2", "великденска кампания и т.н.").

### 2. Refactor `the-marketer/promo-codes.php`

`public_html/citte/the-marketer/promo-codes.php:46` — INSERT-ва в `promo_codes`, не в `loyality_points`.

Mapping:
- `kod` → `code`
- `tip=0` → `type='fixed'`
- `tip=1` → `type='percent'`
- `tip=2` → `type='shipping'`
- `value` → `discount_value`
- `data_validen` (varchar YYYYMMDDHHmmss) → `expiration_date` (DATE, parse-нат)
- `ot_kade='the-marketer'` → `source='the-marketer'`
- `sait` → `site` (ако запазим колоната)

API response остава същият (`code`, `value`, `type`, `expiration`) — The Marketer не вижда промяната.

### 3. One-time migration на съществуващи редове

```sql
-- loyality_points → promo_codes
INSERT IGNORE INTO promo_codes
  (code, type, discount_value, expiration_date, active, source, site, note)
SELECT kod,
       CASE tip WHEN 0 THEN 'fixed' WHEN 1 THEN 'percent' WHEN 2 THEN 'shipping' END,
       value,
       STR_TO_DATE(LEFT(data_validen,8), '%Y%m%d'),
       IF(data_validen > DATE_FORMAT(NOW(),'%Y%m%d%H%i%s'), 1, 0),
       'the-marketer',
       sait,
       komentar
FROM loyality_points
WHERE kod IS NOT NULL AND kod <> '';

-- obshti_kodove → promo_codes
INSERT IGNORE INTO promo_codes
  (code, type, discount_value, expiration_date, active, source, site, note)
SELECT kod,
       CASE tip WHEN 0 THEN 'fixed' WHEN 1 THEN 'percent' WHEN 2 THEN 'shipping' END,
       value,
       STR_TO_DATE(LEFT(data_validen,8), '%Y%m%d'),
       IF(data_validen > DATE_FORMAT(NOW(),'%Y%m%d%H%i%s'), 1, 0),
       'manual',
       sait,
       komentar
FROM obshti_kodove
WHERE kod IS NOT NULL AND kod <> '';
```

`INSERT IGNORE` гарантира, че ако някой код вече съществува в `promo_codes`, миграцията не fails (защото `code` е UNIQUE).

### 4. Decommission на старите таблици

- `porachki.promo_kod` — colonata вече не е нужна; новата система ползва `order_promo_codes`. DROP след като се увериш, че няма live четене на тази колона никъде в emart кода (също провери и в admin/backoffice кода).
- `DROP TABLE loyality_points` и `DROP TABLE obshti_kodove` — едва след като:
  - Миграцията е минала успешно (verify counts: `SELECT COUNT(*) FROM promo_codes WHERE source = 'the-marketer'` vs original `loyality_points`)
  - The Marketer API работи срещу `promo_codes` поне 1-2 седмици в production без проблеми
  - Никой друг service (admin panel, reporting) не зависи от старите таблици

## Отворени въпроси

Преди да започнем имплементация, трябват отговори на:

1. **Multi-site (`sait` колоната).** Сегашната `promo_codes` няма scope по сайт. Имате ли реален случай, в който един код важи само за `bg` но не и за `ro`? Ако да — добавяме `site`; ако не — пропускаме.

2. **`potrebitel` колоната в старите таблици.** Понякога е `0`, понякога има число (`2`, `5`). Какво е това — `klienti_id` (кой клиент има право да го ползва), или audit поле (кой го е създал)? Това определя дали ни трябва `created_by` или `restricted_to_user` колона.

3. **`komentar` vs structured campaign tag.** В `obshti_kodove` се вижда content тип "ЦГ2"/"ЦГ3" — изглежда се ползват за тагиране на кампания. Имате ли вече concept за campaign/group, или свободен текст (`note`) е достатъчно?

4. **The Marketer compatibility.** API-то връща `type` като 0/1/2 (integer) в JSON отговора (`public_html/citte/the-marketer/promo-codes.php:59`). Това трябва да остане същото за external compatibility — внимаваме само вътрешният INSERT да префвърля в ENUM string.

## Verification план

1. **Преди миграцията:**
   - `SELECT COUNT(*) FROM loyality_points` → запиши broя.
   - `SELECT COUNT(*) FROM obshti_kodove` → запиши броя.
   - `SELECT COUNT(*) FROM promo_codes` → baseline.

2. **След миграцията:**
   - Counts trябва да съвпадат: `new promo_codes count == old + (loyality_points + obshti_kodove) − duplicate codes`.
   - Sample проверки за конкретни кодове (`VELIKDEN10`, `slujeben10`, един от The Marketer кодовете).

3. **The Marketer API smoke test:**
   ```
   curl 'https://dev/themarketer/code-generator?key=...&value=10&type=1&expiration_date=2027-01-01%2009:00'
   ```
   - Очаквания response: 200, валиден JSON, `code` присъства в `promo_codes` с `source='the-marketer'` и `type='percent'`.

4. **Cart end-to-end:**
   - Прилагане на мигриран код в количка — `PromoCode::validate()` трябва да го намери.
   - При финализиране на поръчка — запис в `order_promo_codes`, decrement на `remaining_amount` ако е fixed.

## Критични файлове за справка

- `public_html/citte/the-marketer/promo-codes.php` — API за генериране (текущо в `loyality_points`).
- `public_html/citte/lib/PromoCode.php` — нова логика, цели `promo_codes`.
- `public_html/citte/api/promo-validate.php` и `promo-cart.php` — нови AJAX endpoints.
- `public_html/citte/api/promo-validate-table.sql` — DDL за `promo_codes` + sister tables.
- `mysql-dumps/promo-codes-docs.md` — пълна документация на новата система.
- `mysql-dumps/imartap.sql:29845` — `loyality_points` schema.
- `mysql-dumps/imartap.sql:46091` — `obshti_kodove` schema.
- `mysql-dumps/imartap.sql:541501` — коментар на `porachki.promo_kod`, обяснява историческото намерение.
