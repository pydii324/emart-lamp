# Promo — Wholesale × процент промо (compare-and-pick-lower) + `used_by_employeeId`

Продължение на issue [#610](https://github.com/drago1520/emart-gitlab-github-migration/issues/610) след Phase 2.

> **ВАЖНО — смяна на подход.** Първоначално имплементирахме **пълен блок** на промо кодове за wholesale групи (`grupa_otstapki ∈ {2,3}`). drago уточни, че НЕ това се иска. Блокът е **върнат (reverted) изцяло**. Виж Part A.

---

## Part A — Процент промо × wholesale: compare-and-pick-lower (БЕЗ нов код)

### Изискване (drago)
Не следим wholesale групи. За **процент** код: смятай го върху **основната цена** (`it_osnovna_cena`) и вземи по-ниската цена per артикул:
- ако wholesale цената е по-ниска от `основна × (1−%)` → приложи **само wholesale** (промо дава 0);
- ако `основна × (1−%)` е по-ниска → приложи **промо кода върху основната цена**.

### Това вече е имплементирано в [PromoCalc.php:54-81](public_html/citte/lib/PromoCalc.php#L54)
```php
$u1   = $cur / $br;                                  // Phase 1 unit = wholesale цена (за групов клиент)
$effU = min($u1, round($osn * (1 - $pct/100), 2));   // min(wholesale, основна×(1−%))
```
Защо работи коректно (трите ценови фази):
| Фаза | Носител | За wholesale клиент |
|---|---|---|
| 0 | `it_osnovna_cena` | retail базова цена ([v_case.php:267](public_html/citte/v_case.php#L267): `catalog.cena × курс`, БЕЗ групова отстъпка) |
| 1 | `it_cena`/`it_suma` → `phase1_suma` | **wholesale груповата цена** (`cenni()` прилага `grupa_otstapki` при add-to-cart) |
| 2 | PromoCalc | `min(phase1, osnovna×(1−%))` per артикул |

→ Процентът се смята от основната цена; ако паднеш под wholesale — pick wholesale. Точно искането.

### Числова проверка (standalone PromoCalc тест)
Wholesale=8.00, osnovna=10.00:
```
10% код: osnovna×0.9=9.00 > 8.00 → промо=0.00, финал=8.00  (само wholesale)
30% код: osnovna×0.7=7.00 < 8.00 → промо=1.00, финал=7.00  (промо на основната)
retail (без wholesale) 10%: → 9.00
```
Всички минават. (Тестът е ad-hoc, не персистнат.)

### Reverted (върнато към оригинала)
Блокът, който беше добавен и после махнат — без следи:
- [lib/PromoCode.php](public_html/citte/lib/PromoCode.php) — махнати `WHOLESALE_GROUPS`/`blocksPromo()`; `validate()` и `revalidate()` без `grupaOtstapki` param.
- [lib/db-switch.php](public_html/citte/lib/db-switch.php) — `promo_recalc()` без зареждане на `grupa_otstapki`.
- [api/promo-validate.php](public_html/citte/api/promo-validate.php) + [api/promo-cart.php](public_html/citte/api/promo-cart.php) — `sesii` заявката върната без join към `klienti`.
- [citte/promo-input.php](public_html/citte/promo-input.php) — махнат UI gate / съобщението.
- i18n ключ `3106` — не е нужен.

`grep` потвърждава: нула `blocksPromo|WHOLESALE|grupaOtstapki` референции остават.

---

## Part B — `used_by_employeeId` (само schema, БЕЗ storefront връзка) — ЗАПАЗЕНО

Несвързано с Part A; остава както беше.

- **Файл:** [mysql-dumps/promo_codes/11-add-used-by-employee.sql](mysql-dumps/promo_codes/11-add-used-by-employee.sql)
- **Колона:** `order_promo_codes.used_by_employeeId INT NULL DEFAULT NULL`
- Idempotent + table-existence guarded, таргетира `DATABASE()` (като [08](mysql-dumps/promo_codes/08-add-phase2-columns.sql)). `order_promo_codes` е само в `imartap` → no-op срещу региони.
- Попълва се от **админската част** (отделен проект). Storefront НЯМА служител session → `markUsed()` НЕ е пипан; редове от storefront остават `NULL`.

---

## Part C — `min_subtotal` след отстъпки
**Без код.** `validate()`/`revalidate()` сравняват срещу `CartItems::subtotal()` = `SUM(it_suma + discount_applied)` = post-Phase-2 цена.

---

## DB миграции

| # | Файл | Какво | Къде |
|---|---|---|---|
| 11 | [11-add-used-by-employee.sql](mysql-dumps/promo_codes/11-add-used-by-employee.sql) | `order_promo_codes.used_by_employeeId INT NULL` | `imartap` (no-op за региони) |

**Изпълнение** (per region) през `emart-monorepo/packages/db/scripts/batch-sql-dbs/sql-batch-dbs.ts`, като 08/09/10. Re-run = no-op.

```sql
-- 11-add-used-by-employee.sql (guard pattern като 08)
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'order_promo_codes')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'order_promo_codes' AND COLUMN_NAME = 'used_by_employeeId'),
  'ALTER TABLE `order_promo_codes` ADD COLUMN `used_by_employeeId` INT NULL DEFAULT NULL COMMENT ''Employee who used the code (admin/backoffice app; legacy obshti_kodove.potrebitel)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
```

> Миграцията НЕ изпълнена срещу базата (DB не runnable локално — `zamysql.php` gitignored). Чака staging/production run.

---

## Състояние на кода
- 5-те PHP файла (PromoCode, db-switch, promo-validate, promo-cart, promo-input) → върнати към оригинала, `php -l` clean.
- PromoCalc.php → непроменян; вече прави compare-and-pick-lower.
- Само нов файл: миграция `11`.

## За production / staging
- [ ] Изпълни миграция `11` на `imartap`.
- [ ] Staging проверка: wholesale клиент + процент код → провери че финалната цена per артикул = `min(wholesale, основна×(1−%))`.
- [ ] (Отделен проект) админ app да попълва `used_by_employeeId`.

## Отворени въпроси (drago)
1. Поведение при **fixed (ваучер)** и **shipping** кодове за wholesale клиент — остават нормални (махат от subtotal/доставка). Изискването беше само за **процент**. Потвърди ако трябва друго.
2. (По-късно) The Marketer min order value на код-създаване в `promo-codes.php`.
