# Promo — Wholesale блок + `used_by_employeeId`

Имплементация на issue [#610](https://github.com/drago1520/emart-gitlab-github-migration/issues/610) (продължение след Phase 2). Три искания от drago:

1. **Wholesale блок** — клиент с отстъпка на едро (`klienti.grupa_otstapki` ∈ {2,3}) не може да ползва промо кодове изобщо; показва се съобщение защо.
2. **`used_by_employeeId`** — нова колона за проследяване кой служител е ползвал кода (легаси `imartap.obshti_kodove.potrebitel`). Само schema — попълва се от админската част (отделен проект).
3. **`min_subtotal` след всички отстъпки** — вече покрито от Phase 2 (`CartItems::subtotal()` = `SUM(it_suma)`, post-discount). **Без код.**

---

## Как работи `grupa_otstapki`

`klienti.grupa_otstapki` INT (0–8): `0` = дребно (retail), `1–8` = ценова група на едро. Каталогът има 8 цени на продукт (`p_cengr_1…p_cengr_8`); `cenni()` ([ceni/cenni.php](public_html/ceni/cenni.php#L34)) ползва `$cengr_f = $p_gr_otst_klie` → клиент с група > 0 плаща груповата цена на всеки продукт. Зарежда се в [sesii.php:546](public_html/citte/sesii.php#L546) → `$p_gr_otst_klie`. Т.е. wholesale клиент вече има отстъпка → drago иска да НЕ трупа отгоре и промо код.

`{2,3}` са в **конфигуруема константа** `PromoCode::WHOLESALE_GROUPS` — смяна без друг code edit.

---

## Part A — Wholesale блок (3 слоя защита)

Защита на UI + server validate/apply + recalc, за да не се заобикаля.

| Слой | Файл | Промяна |
|---|---|---|
| Константа + helper | [lib/PromoCode.php](public_html/citte/lib/PromoCode.php) | `const WHOLESALE_GROUPS = [2,3]` + `static blocksPromo(int $grupa): bool` |
| Validate (apply) | [lib/PromoCode.php](public_html/citte/lib/PromoCode.php) | `validate(..., int $grupaOtstapki = 0)` — при `blocksPromo()` връща `['valid'=>false,'error'=>'Имате клиентска отстъпка на едро — промо кодове не важат.']` веднага след празен-код проверката |
| Revalidate (recalc) | [lib/PromoCode.php](public_html/citte/lib/PromoCode.php) | `revalidate(..., int $grupaOtstapki = 0)` — при `blocksPromo()` `$blockAll=true` → drop ВСИЧКИ редове (същата DELETE логика). Покрива: гост слага код → логва се като wholesale |
| Recalc orchestrator | [lib/db-switch.php](public_html/citte/lib/db-switch.php) | `promo_recalc()` чете `grupa_otstapki` за `$po` **регионално** (преди imartap swap, `klienti` е регионална) и подава в `revalidate()` |
| API validate | [api/promo-validate.php](public_html/citte/api/promo-validate.php) | `sesii` заявката `LEFT JOIN klienti` → `$grupa`; `validate($kod,$cartTotal,$po,$appliedIds,$grupa)` |
| API apply | [api/promo-cart.php](public_html/citte/api/promo-cart.php) | същият join + `validate(...,$grupa)`; блокът връща `valid=false` → съществуващият error path показва съобщението |
| UI gate | [citte/promo-input.php](public_html/citte/promo-input.php) | при `PromoCode::blocksPromo($p_gr_otst_klie)` рендира съобщение (`$prevodite[3106]`) и `return` — без input/chips/JS |

**Поведение:**
- **Guest** (`$po=0`) → няма група → промо разрешен (`COALESCE(...,0)`).
- **grupa ∈ {2,3}** → блокиран на трите слоя.
- **grupa ∈ {0,1,4–8}** → промо работи (regression-safe).

**SQL pattern за зареждане на групата** (двата API):
```sql
SELECT s.po, s.pe, COALESCE(k.grupa_otstapki, 0) AS grupa
FROM sesii s LEFT JOIN klienti k ON k.klienti_id = s.po
WHERE s.sesii_id = '$tuksus' LIMIT 1;
```

**i18n:** нов ключ `3106` (промо ползва 3100–3105). Стойност: „Имате клиентска отстъпка на едро — промо кодове не важат." Кодът има fallback default → работи и без вписан превод.

---

## Part B — `used_by_employeeId` (само schema, без storefront връзка)

Колоната е за **админската част** (отделен проект). Storefront НЯМА служител session (`the-marketer` = външно REST API; `potrebitel` навсякъде = клиентът) → storefront не я пипа. `markUsed()` НЕ е променян → редове от storefront остават `NULL`; админ app-ът попълва.

- **Файл:** [mysql-dumps/promo_codes/11-add-used-by-employee.sql](mysql-dumps/promo_codes/11-add-used-by-employee.sql)
- **Колона:** `order_promo_codes.used_by_employeeId INT NULL DEFAULT NULL`
- Idempotent + table-existence guarded, таргетира `DATABASE()` (като [08](mysql-dumps/promo_codes/08-add-phase2-columns.sql)). `order_promo_codes` е само в `imartap` → no-op срещу регионалните.

---

## Part C — `min_subtotal` след отстъпки
**Без код.** `validate()`/`revalidate()` сравняват срещу `CartItems::subtotal()` = post-Phase-2 цена. drago: „вече добавено".

---

## DB миграции

| # | Файл | Какво | Къде |
|---|---|---|---|
| 11 | [11-add-used-by-employee.sql](mysql-dumps/promo_codes/11-add-used-by-employee.sql) | `order_promo_codes.used_by_employeeId INT NULL` | `imartap` (no-op за региони) |

**Изпълнение** (per region) през `emart-monorepo/packages/db/scripts/batch-sql-dbs/sql-batch-dbs.ts`, същия начин като 08/09/10. Re-run = no-op (idempotent).

```sql
-- 11-add-used-by-employee.sql (същия guard pattern като 08)
SET @ddl := (SELECT IF(
  EXISTS(SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'order_promo_codes')
  AND NOT EXISTS(SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'order_promo_codes' AND COLUMN_NAME = 'used_by_employeeId'),
  'ALTER TABLE `order_promo_codes` ADD COLUMN `used_by_employeeId` INT NULL DEFAULT NULL COMMENT ''Employee who used the code (admin/backoffice app; legacy obshti_kodove.potrebitel)''',
  'DO 0'));
PREPARE st FROM @ddl; EXECUTE st; DEALLOCATE PREPARE st;
```

> Бележка: миграцията НЕ изпълнена срещу базата (app/DB не runnable локално — `zamysql.php` gitignored). Чака staging/production run.

---

## Проверено
- `php -l` на всички 5 променени PHP файла → clean.
- Логика на `revalidate()` branch chain → запазена (`$blockAll` fall-through, иначе старите elseif проверки).
- Class scope: `db-switch.php` (`require_once PromoCode.php`) зареден в [case.php:24](public_html/citte/case.php#L24) преди include на promo-input.php ([case.php:573](public_html/citte/case.php#L573)) → `PromoCode::blocksPromo()` достъпен.

## За production / staging
- [ ] Изпълни миграция `11` на `imartap` (+ безопасна за региони).
- [ ] Впиши i18n ключ `3106` (има fallback default).
- [ ] Потвърди с drago дали `{2,3}` са точните wholesale групи (срещу 1–8) → ако не, смени само `PromoCode::WHOLESALE_GROUPS`.
- [ ] Staging end-to-end: grupa 2/0/1 + guest→login сценарии (виж плана).

## Отворени въпроси (drago)
1. Wholesale групи: точно `{2,3}`?
2. (По-късно) The Marketer min order value на код-създаване в `promo-codes.php`.
