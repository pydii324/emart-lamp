# Система за промо кодове

> Последно обновено: 2026-05-14. Замества предишната версия с новата консолидирана схема (виж `promo-codes-master-plan.md`).
>
> Тази версия консолидира `loyality_points` + `obshti_kodove` + `promo_codes` в единна `promo_codes` таблица. Старите таблици остават read-only за reference.

---

## База данни

### Конвенция за дати

Всички date/time колони в `promo_codes` / `cart_promo_codes` / `order_promo_codes` са `VARCHAR(14)` в `YYYYMMDDHHmmss` формат — съответства на PHP `date('YmdHis')`. Lexicographic comparison работи коректно за подреждане и сравнение. Това е установената конвенция в `imartap` (виж `loyality_points.data_sazdaden`, `obshti_kodove.data_validen`).

### Таблица `promo_codes`

```sql
CREATE TABLE `promo_codes` (
  `id`                INT          NOT NULL AUTO_INCREMENT,
  `code`              VARCHAR(50)  NOT NULL,
  `type`              ENUM('percent','fixed','shipping') NOT NULL DEFAULT 'percent',

  -- Стойност
  `discount_value`    DECIMAL(10,2) NOT NULL,
  `voucher_remainer`  DECIMAL(10,2) NULL DEFAULT NULL,

  -- Ограничения
  `min_subtotal`      DECIMAL(10,2) NOT NULL DEFAULT 0,
  `shipping_cap`      DECIMAL(10,2) NULL DEFAULT NULL,
  `max_uses`          INT          NOT NULL DEFAULT 0,
  `times_used`        INT          NOT NULL DEFAULT 0,

  -- Поведение
  `active`            BOOLEAN      NOT NULL DEFAULT TRUE,
  `stack_group`       TINYINT      NULL DEFAULT NULL,

  -- Дати (VARCHAR(14) YYYYMMDDHHmmss)
  `expiration_date`   VARCHAR(14)  NULL DEFAULT NULL,
  `created_at`        VARCHAR(14)  NOT NULL,
  `used_at`           VARCHAR(14)  NULL DEFAULT NULL,

  -- Произход / metadata
  `source`            ENUM('the-marketer','manual','bulk-import') NOT NULL DEFAULT 'manual',
  `note`              VARCHAR(255) NULL DEFAULT NULL,
  `site`              VARCHAR(10)  NULL DEFAULT NULL,
  `created_by`        VARCHAR(255) NULL DEFAULT NULL,

  PRIMARY KEY (`id`),
  UNIQUE KEY `code` (`code`),
  KEY `idx_active_exp` (`active`, `expiration_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

| Колона | Описание |
|---|---|
| `type` | `percent` = процент от сумата; `fixed` = ваучер (фиксирана сума); `shipping` = отстъпка от доставка |
| `discount_value` | Стойност на отстъпката (процент или сума) |
| `voucher_remainer` | Само за `fixed` — наличен бюджет; намалява при всяка употреба. Бивш `remaining_amount`. |
| `min_subtotal` | Минимална стойност на количката за активиране |
| `shipping_cap` | Само за `shipping` — максимална доставка за покриване; `NULL` = покрива всичко |
| `max_uses` | Брой употреби общо; `0` = безлимитно; `1` = single-use (the-marketer кодове) |
| `times_used` | Брояч на употреби; incremenет-ва се при `markUsed()` чрез `times_used = times_used + 1` |
| `active` | Manual on/off switch |
| `stack_group` | `NULL` = комбинира се с всичко; число = само 1 код от групата може да е активен |
| `expiration_date` | Краен срок (VARCHAR(14)); `NULL` = без срок |
| `created_at` | Кога е създаден кодът (винаги се сетва при INSERT) |
| `used_at` | Last-used timestamp; update-ва се при `markUsed()` |
| `source` | Произход: `'the-marketer'` (auto-generated), `'manual'` (ръчно през admin), `'bulk-import'` (масово зареден) |
| `note` | Свободно поле за коментар (бивш `komentar` от старите таблици) |
| `site` | Site scope: `'bg'`, `'ro'`, `'gr'`, `'all'`; `NULL` = unscoped (бивш `sait`) |
| `created_by` | Free-form audit поле (бивш `ot_kade`) |

### Таблица `cart_promo_codes`

Съхранява кодовете, приложени към текущата количка (изтрива се при финализиране).

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
  `created_at`       VARCHAR(14)  NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_cart_promo` (`cart_id`,`cart_type`,`promo_code_id`),
  CONSTRAINT `fk_cpc_promo` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

`cart_type`: `'l'` = логнат потребител (`porachki_l`); `'no'` = гост (`porachki_no`)

### Таблица `order_promo_codes`

Записва финализираните употреби на кодове при потвърдена поръчка.

```sql
CREATE TABLE `order_promo_codes` (
  `id`               INT          NOT NULL AUTO_INCREMENT,
  `order_id`         INT          NOT NULL,
  `promo_code_id`    INT          NOT NULL,
  `klienti_id`       INT          NOT NULL DEFAULT 0,
  `discount_applied` DECIMAL(10,2) NOT NULL,
  `created_at`       VARCHAR(14)  NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_order_promo` (`order_id`,`promo_code_id`),
  CONSTRAINT `fk_opc_promo` FOREIGN KEY (`promo_code_id`) REFERENCES `promo_codes` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

---

## Стари таблици (deprecated, read-only)

`loyality_points` и `obshti_kodove` остават след миграцията само за reference / audit / reconciliation срещу external systems (The Marketer dashboard). PHP кодът не пише и не чете от тях.

| Стара таблица | Брой редове (2026-05-14) | Замяна |
|---|---|---|
| `loyality_points` | 16,221 | `promo_codes` (source='the-marketer', max_uses=1) |
| `obshti_kodove` | 17 (3 test-rows с NULL tip се изключват) | `promo_codes` (source='manual', max_uses=0) |

---

## Файлова структура

```
citte/
├── lib/
│   └── PromoCode.php          # Основен клас — валидация, изчисления, запис
├── api/
│   ├── promo-validate.php     # AJAX endpoint — валидира и прилага код към количката
│   ├── promo-cart.php         # AJAX endpoint — управление (добавяне/премахване)
│   └── promo-validate-table.sql  # DDL за трите таблици + тестови данни
├── the-marketer/
│   └── promo-codes.php        # API за auto-generation от The Marketer (пише в promo_codes)
├── promo-input.php            # UI компонент — полето за въвеждане на код
├── promo-cart-rows.php        # UI компонент — редове в таблицата с ценообразуване
└── case.php                   # Количка — интегрира PromoCode и двата UI компонента
```

---

## Клас `PromoCode` (`citte/lib/PromoCode.php`)

### Методи

| Метод | Описание |
|---|---|
| `validate($code, $cartTotal, $po, $appliedIds)` | Валидира код — проверява активност, срок, минимум, лимити, stack_group конфликти |
| `getCartTotal($tuksus, $po, $pe)` | Взима текущия subtotal от `item_no` или `item_l` |
| `getAppliedForCart($cartId, $cartType)` | Връща приложените кодове за количката с актуални данни от `promo_codes` |
| `applyCartDiscounts(&$promos, $origSubtotal, $cartId, $cartType, $items)` | Преизчислява и записва отстъпките за `percent` и `fixed` кодове |
| `applyShippingDiscount(&$promos, $origShipping, $cartId, $cartType)` | Преизчислява и записва отстъпката за `shipping` кодове |
| `finalizeForOrder($cartId, $cartType, $orderId, $po)` | При потвърдена поръчка — маркира употребите и изчиства `cart_promo_codes` |
| `markUsed($promoId, $orderId, $discountApplied, $po)` | INSERT в `order_promo_codes`, UPDATE на `promo_codes.used_at` и `times_used = times_used + 1`, намалява `voucher_remainer` при `fixed` |

### Сравнение на дати

`expiration_date` сравнението е string-based (lexicographic на `YYYYMMDDHHmmss`):

```php
if ($r['expiration_date'] && $r['expiration_date'] < date('YmdHis')) {
    // изтекъл
}
```

Не използваме `strtotime()` — VARCHAR(14) форматът е lexicographic-sortable, директното сравнение е по-бързо и без timezone gotchas.

---

## Логика на изчисление

### `percent` тип — per-item сравнение

За всеки артикул в количката се сравняват две цени и се избира по-ниската:

```
promoPrice_i = osnovna_cena_i × qty_i × (1 - promo% / 100)
effective_i  = min(it_suma_i, promoPrice_i)
discount_i   = it_suma_i - effective_i
```

**Сценарии:**

| Артикул | `it_suma` (намалена) | `osnovna × qty` (каталожна) | При 40% промо | Резултат |
|---|---|---|---|---|
| Голяма продуктова отстъпка | 50 лв. | 100 лв. | 60 лв. | Пази намалената (50 лв.) |
| Малка продуктова отстъпка | 90 лв. | 100 лв. | 60 лв. | Ползва промото (60 лв.) |
| Без отстъпка | 100 лв. | 100 лв. | 60 лв. | Ползва промото (60 лв.) |

Ако `it_osnovna_cena = 0` (артикулът няма записана каталожна цена) — промото се прилага върху намалената цена като fallback.

### `fixed` тип — ваучер

Маха се от текущия subtotal без сравнение. Не взима предвид продуктови отстъпки.

```
discount = min(voucher_remainer, subtotal)
```

`voucher_remainer` намалява при всяка употреба (проследява се общ бюджет).

### `shipping` тип

```
deduction = shipping_cap IS NULL ? full_shipping : min(shipping_cap, shipping_cost)
```

---

## Поток при количката (`case.php`)

```
1. getAppliedForCart()       — зарежда приложените кодове
2. applyCartDiscounts()      — преизчислява percent/fixed, записва в cart_promo_codes
   └── per-item логика       — $_promoItems (it_suma + osnovna × qty за всеки артикул)
3. promo-cart-rows.php       — показва редовете с отстъпките в таблицата
4. applyShippingDiscount()   — преизчислява shipping, записва в cart_promo_codes
5. promo-cart-rows.php       — показва реда за доставна отстъпка
6. Крайна сума:
   porobst = subtotal - cartDiscount + shipping - shipDiscount
```

---

## Валидации при прилагане на код

1. Код съществува и е активен (`active = 1`)
2. Не е изтекъл (string compare на `expiration_date` срещу `date('YmdHis')`)
3. Количката покрива `min_subtotal`
4. Кодът не е вече приложен в тази количка
5. `stack_group` конфликт — само 1 код от групата
6. `max_uses` — не е достигнат общият лимит (`times_used < max_uses`)
7. `fixed` тип — `voucher_remainer > 0`

---

## Тестови промо кодове (dev среда)

| Код | Тип | Стойност | Условие | Бележка |
|---|---|---|---|---|
| `TEST10` | percent | 10% | — | Без ограничения |
| `TEST20MIN` | percent | 20% | мин. 30 лв. | Лимит 5 употреби |
| `FIXED5` | fixed | 5 лв. | — | Бюджет 50 лв. |
| `FIXED15` | fixed | 15 лв. | мин. 40 лв. | 1 употреба/потребител |
| `FREESHIP` | shipping | до 10 лв. | — | Покрива доставка до 10 лв. |
| `SHIPALL` | shipping | без лимит | мин. 20 лв. | Пълна безплатна доставка |
| `EXPIRED` | percent | 15% | — | Изтекъл (за тест на валидация) |
| `INACTIVE` | percent | 25% | — | Неактивен |
| `STACK1A` | percent | 10% | — | Група 1 — не се комбинира с `STACK1B` |
| `STACK1B` | fixed | 5 лв. | — | Група 1 — не се комбинира с `STACK1A` |
