# План: Промо кодът да сравнява с цената от `cenni()`

## Context

В момента, когато се прилага промо код от тип `percent`, логиката в `PromoCode::applyCartDiscounts()` (`public_html/citte/lib/PromoCode.php:192-208`) сравнява **намалената цена** (`it_suma`) с **каталожната × (1 - promo%)**, и взима по-ниската. За "каталожна цена" се ползва колоната `it_osnovna_cena` от `item_l`/`item_no`, която се попълва в `case.php:131-138` директно от `catalog.cena`:

```php
$queri = "SELECT ... cena FROM catalog WHERE cat_no = '...';";
$it_osnovna_cena_col[$i] = $row[7] * $koeffvalutt;
```

**Проблем:** Тази "сурова" `catalog.cena` не отразява клиент-специфичните цени (ценова група, меню отстъпки, голям пакет, количествени отстъпки). Системата вече има функция `cenni()` (`public_html/ceni/cenni.php`), която връща до 6 цени за артикул със слот `[1]` винаги съдържащ правилната "osnavna" според контекста (вж. `c050.php`, `c052.php`, `c053.php` и т.н., които винаги поставят `$pisha[1][1] = $osn_cena` с `[2] = 1`). Идентичният pattern се ползва вече в `stoki_ceni.php:131` (`$mostExpensive = (float)$zanapsani[1][1] * $koeffvalutt`).

**Цел:** Промо кодът от тип `percent` да сравнява с `cenni()`-базирана osnovna цена, не със суровата `catalog.cena`.

## Подход

Запазваме съществуващия flow — `it_osnovna_cena` остава колоната-носител, само сменяме **източника** при попълването ѝ в `case.php`. Така `PromoCode.php` остава непроменен.

1. Разширяваме съществуващия SELECT от `catalog` в `case.php:131`, така че да тегли всички колони, нужни на `cenni()`.
2. Подготвяме клиент-специфичните параметри (`$menu_f`, `$cengr_f`, `$zkl_f`, `$log_f`) по същия начин като `v_case.php:143-150` — използваме вече заредените глобали (`$p_otstapka_klie`, `$p_gr_otst_klie`, `$p_zakluchen_klie`, `$m1gro`, `$m2gro`, `$m3gro`).
3. Викаме `cenni()` за всеки артикул и записваме `$zanapsani[1][1] * $koeffvalutt` в `$it_osnovna_cena_col[$i]`.
4. Защитно — ако `$zanapsani[1][1]` не съществува или е ≤ 0, fallback към `catalog.cena` (сегашното поведение).

## Файлове за промяна

Един файл: **`public_html/citte/case.php`** (само блокът на ред 127-157).

Без промени в:
- `public_html/citte/lib/PromoCode.php` — логиката за сравнение остава същата.
- `public_html/ceni/cenni.php` — реюзваме както е.
- Схемата на БД — `it_osnovna_cena` остава носител.

## Детайлни промени

### `case.php:131` — разширен SELECT

Сегашен:
```php
$queri = "SELECT nalichnost, q_total, q_new2, obem_total, obem_dalzhina, obem_visochina, obem_shirina, cena FROM catalog WHERE cat_no = '".$cat_no_col[$i]."';";
```

Нов — добавят се `gr_otst, br_1, cena_1, br_2, cena_2, br_3, cena_3, p_cengr_1..8, p_koeftr, menu_gl, menu, menu_pod`. Точно същият набор колони, който `v_case.php:84` използва (минус полета като `cat_no`, `ime`, които вече имаме).

### `case.php:131-138` — попълване на `$*_f` за `cenni()`

След while loop-а, който чете catalog данните, по подобие на `v_case.php:87-113`:
```php
$cen_f = $row[7];       # catalog.cena (osnovna)
$prce_f = $row[8];      # gr_otst
$br1_f = $row[9]; $cena1_f = $row[10];
$br2_f = $row[11]; $cena2_f = $row[12];
$br3_f = $row[13]; $cena3_f = $row[14];
$cgr1_f = $row[15]; ... $cgr8_f = $row[22];
$zabr_f = $row[23];     # p_koeftr
$menu_gl_f = $row[24]; $menu_f_raw = $row[25]; $menu_pod_f = $row[26];
```

### `case.php` — client-specific params

Точно копие на `v_case.php:143-150` (опростено за случая на cart, без INSERT-овете в porachki_l):
```php
if ($po > 0) {
    if (($menu_pod_f > 0) && (isset($m3gro[$menu_pod_f])) && ($m3gro[$menu_pod_f] > 0))
        $menu_f = $p_otstapka_klie[$m3gro[$menu_pod_f]];
    elseif (($menu_f_raw > 0) && (isset($m2gro[$menu_f_raw])) && ($m2gro[$menu_f_raw] > 0))
        $menu_f = $p_otstapka_klie[$m2gro[$menu_f_raw]];
    elseif (($menu_gl_f > 0) && (isset($m1gro[$menu_gl_f])) && ($m1gro[$menu_gl_f] > 0))
        $menu_f = $p_otstapka_klie[$m1gro[$menu_gl_f]];
    else $menu_f = 0;
    $zkl_f = $p_zakluchen_klie;
    $log_f = 2;
    $cengr_f = $p_gr_otst_klie;
} else {
    $menu_f = 0; $zkl_f = 0; $log_f = 0; $cengr_f = 0;
}
```

### `case.php` — извикване на `cenni()` и попълване на `$it_osnovna_cena_col`

```php
if (!function_exists("cenni")) require($koren_pat . "ceni/cenni.php");
$zanapsani = cenni($menu_f, $cengr_f, $zkl_f, $log_f, $cen_f,
                   $cgr1_f, $cgr2_f, $cgr3_f, $cgr4_f, $cgr5_f, $cgr6_f, $cgr7_f, $cgr8_f,
                   $zabr_f, $prce_f,
                   $br1_f, $cena1_f, $br2_f, $cena2_f, $br3_f, $cena3_f);

$osnFromCenni = (isset($zanapsani[1][1]) && (float)$zanapsani[1][1] > 0)
    ? (float)$zanapsani[1][1]
    : (float)$cen_f;  // fallback към суровата catalog.cena
$it_osnovna_cena_col[$i] = number_format($osnFromCenni * $koeffvalutt, 2, '.', '');
```

Точният път до `ceni/cenni.php` се проверява спрямо `$koren_pat` (вече се ползва на други места в `case.php`) — ако променливата не е валидна тук, изваждам пътя релативно като в `v_case.php:189` (`require("ceni/cenni.php")`).

## Verification

1. **Sanity check на dev средата** (`docker-compose up`):
   - Логнат потребител без ценова група → `$it_osnovna_cena` трябва да е същата като преди (тъй като `cenni()` връща суровата osnovna в slot [1]).
   - Логнат потребител с ценова група, в която артикул има специална цена → `$it_osnovna_cena` следва да отразява тази контекстуална цена, а не суровата `catalog.cena`.
   - Гост → resultatът от `cenni()` с `log_f=0` следва да е идентичен със суровата `catalog.cena`, защото всички клиент-специфични входове са 0.

2. **Тестови сценарии с промо кодове** (от `mysql-dumps/promo-codes-docs.md` — тестови данни):
   - `TEST10` (10% percent) върху артикул с продуктова отстъпка → потвърждаваме че `effective = min(it_suma, osnovna_от_cenni × (1 - 10%))`.
   - `TEST20MIN` (20%) върху артикул в ценова група → `osnovna` идва от `cenni()`-логиката, не директно от `catalog.cena`.
   - `FIXED5` и `FREESHIP` → не трябва да са засегнати (различен tip).

3. **Регресия:**
   - Преди промяната — `SELECT it_osnovna_cena FROM item_l WHERE porach_id = X;` → записва се стойност `V1`.
   - След промяната за същия cart/клиент — `V2`. За logged-out клиент `V1 == V2` (без regression). За logged-in с ценова група — `V2` може да се различава (очаквано).

4. **MCP проверка** (използваме `mcp__mysql-all-dbs__mysql_query`) — преди и след промяната:
   ```sql
   SELECT cat_id, it_osnovna_cena, it_suma FROM item_no WHERE porach_id = <test_session>;
   ```

5. **Performance**: разширеният SELECT добавя ~17 колони към съществуваща заявка по `cat_no` — без допълнителни roundtrips. Cenni() е чист PHP без I/O. Не очакваме измеримо забавяне.

## Критични файлове за справка

- `public_html/citte/case.php:24-49` — четене на cart items от `item_l`/`item_no` (тук взимаме `cat_no_col`, `item_br_col`, `cat_id_col`).
- `public_html/citte/case.php:127-157` — блокът, който модифицираме (catalog refresh + INSERT в items).
- `public_html/citte/case.php:217-296` — building на `$_promoItems` и викане на `PromoCode::applyCartDiscounts()` — **без промени тук**, само consumer на `$it_osnovna_cena_col`.
- `public_html/citte/v_case.php:84-150` — reference pattern за SELECT и client-specific логиката за menu/zkl/log/cengr.
- `public_html/ceni/cenni.php:34-313` — самата функция и нейните 6-slot изход.
- `public_html/citte/lib/PromoCode.php:192-208` — consumer на osnovna в per-item percent логиката (без промени).
