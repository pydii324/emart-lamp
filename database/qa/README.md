# QA фикстури за промо кодовете — runbook

Ръчно тестване на issue #610 през фронтенда. Тази директория **не е миграция** —
файловете тук се пускат колкото пъти трябва и не влизат на продукция.

- `promo-codes-qa-seed.sql` — 16 кода в `imartap.promo_codes`, маркирани `created_by='qa-seed'`

---

## Пускане

```bash
cd /home/pydi-ubuntu/projects/emart-lamp
docker exec -i lamp-mysql8 mysql -uroot -ptiger --default-character-set=utf8mb4 --table \
  -D imartap < database/qa/promo-codes-qa-seed.sql
```

Накрая печата таблица с всички фикстури. Файлът първо трие собствените си редове,
така че всяко пускане връща фикстурите в начално състояние — `times_used` се нулира,
изгорените кодове оживяват.

> `promo_codes.id` се сменя при всяко пускане (AUTO_INCREMENT не се връща назад).
> Ползвай `code`, не ID, когато пишеш заявки на ръка.

Сайтът: **https://localhost:8453/** (HTTPS е задължително — cookie-тата са `Secure`,
през `http://localhost:8091/` количката мълчаливо не работи).

## Reset между тестовете

Кодовете се нулират с повторно пускане на seed-а. Количките — отделно:

```bash
# Изчиства приложените кодове от всички колички
docker exec lamp-mysql8 mysql -uroot -ptiger -e \
  "DELETE FROM inmarta.cart_promo_codes;"

# Ако е останал закотвен отрицателен промо ред в количка
docker exec lamp-mysql8 mysql -uroot -ptiger -e \
  "DELETE FROM inmarta.item_l  WHERE cat_no IN ('5555555','6666666','7777777','8888888');
   DELETE FROM inmarta.item_no WHERE cat_no IN ('5555555','6666666','7777777','8888888');"
```

## Какво знае средата

| | |
|---|---|
| Региони | **само `bg`** — `citte/zamysql.php` знае `bg`→`inmarta` + `imartap`. Другите региони се тестват на staging или на `emart.al` |
| Валута на bg | `EUR` (`PromoRegion::CURRENCY['bg']`) |
| Етикет на валутата | `promenliviprevodi[99]` в `inmarta` е **`лв.`**, не `EUR`. Дъмпът е отпреди еврото. Съобщението за минимална сума ще каже „50.00 лв." локално — това е **данните на dev базата, не бъг в кода**. На staging трябва да каже валутата на региона |
| Евтини артикули за тест | `cat_no` 102030, 103049, 103014, 103040 — по 2.00 в каталога |

### Прагове на доставката (`inmarta.promenliviprevodi`)

| Стойност на количката | Доставка |
|---|---|
| под 40 | **5.50** (`[6002]`) |
| 40 до 100 | **4.50** (`[6003]`) |
| 100 и нагоре | **0.00** — безплатна (`[6000]`) |

`[6200] = 2`, значи за някои куриери важи цената на куриера (`$ncendoss`), не таблицата.

> **Дръж количката под 40, когато тестваш shipping кодове.** Над 100 доставката
> вече е 0 и няма какво да се сваля — кодът ще изглежда счупен, а не е.

---

## Smoke проверка преди ръчното тестване

Минава всички кодове през реалния API. Изисква количка с поне един артикул
(добави го през браузъра, после подай cookie jar-а):

```bash
J=$(mktemp); curl -sk -c "$J" -o /dev/null https://localhost:8453/
# добави артикул: отвори продукт в браузъра с ?kupi=da, или
# curl -sk -b "$J" -c "$J" -o /dev/null "https://localhost:8453/<slug>?kupi=da"

for C in QAINACTIVE QAEXPIRED QAMIN50 QAUSEDUP QARO QANOSUCH QASTACKA QASTACKB \
         QAFREESHIP QASHIPCAP0 QAVOUCHERBIG; do
  printf "%-14s " "$C"
  curl -sk -b "$J" -X POST -H "X-Requested-With: XMLHttpRequest" \
    -H "Origin: https://localhost:8453" -d "action=apply&kod=$C" \
    https://localhost:8453/citte/api/promo-cart.php; echo
done
```

Очакван изход (проверен на 20.09.2026, количка 5.00):

```
QAINACTIVE     Кодът не е активен
QAEXPIRED      Кодът е изтекъл
QAMIN50        Минимална сума за код: 50.00 лв.
QAUSEDUP       Кодът е изчерпан
QARO           Невалиден код
QANOSUCH       Невалиден код
QASTACKA       success, discount 0
QASTACKB       Не може да се комбинира с вече приложен код от същата група
QAFREESHIP     success, shipping_cap = null
QASHIPCAP0     success, shipping_cap = 0
QAVOUCHERBIG   success, discount 4.50  (капнат на остатъка от количката)
```

`QAFREESHIP` дава `shipping_cap: null`, а `QASHIPCAP0` дава `shipping_cap: 0` —
това е доказателството, че NULL не се е превърнал в 0.00 някъде по пътя.

След smoke-а изчисти количката (виж „Reset между тестовете").

---

## Кодовете

Всички са `site='bg'`, `currency='EUR'`, освен `QARO`.

### Валидация — всеки трябва да бъде отхвърлен

| Код | Очаквано съобщение |
|---|---|
| *(празно поле)* | `Въведи промо код` |
| `QANOSUCH` *(не съществува)* | `Невалиден код` |
| `QARO` | `Невалиден код` — код на `ro`. Умишлено **неразличимо** от несъществуващ, за да не се изброяват чужди кодове |
| `QAINACTIVE` | `Кодът не е активен` — той е И изтекъл, така че това доказва реда: `active` бие `expired` |
| `QAEXPIRED` | `Кодът е изтекъл` |
| `QAMIN50` | `Минимална сума за код: 50.00 лв.` — пусни го с количка **под 50** |
| `QAUSEDUP` | `Кодът е изчерпан` |
| `QAPCT10` два пъти | `Кодът вече е приложен` |
| `QASTACKA` → `QASTACKB` | `Не може да се комбинира с вече приложен код от същата група` |
| който и да е при празна количка | `Количката е празна` |

Редът в `PromoCodeCatalog::rejectionReason()` е `match(true)` отгоре надолу и е контракт:
`active` → `expired` → `min_subtotal` → `вече приложен`. Проверката за `stack_group` е
**преди** `max_uses` — нарочно, за да не се хаби код, който така или иначе не минава.

### Сметки

| Код | Какво прави | Какво да видиш |
|---|---|---|
| `QAPCT10` | 10% | Задраскана стара цена **до артикула**. Никакъв отделен ред |
| `QAPCT20` | 20% | Същото |
| `QAPCT10` + `QAPCT20` заедно | | Прилага се **само 20-те**. 10-те остават в количката с отстъпка 0 и **не** се инвалидират |
| `QAVOUCHER5` | ваучер 5.00 | Отрицателен ред **SKU 5555555** |
| `QACOUPON5` | купон 5.00 | Отрицателен ред **SKU 7777777** |
| `QAVOUCHERBIG` | ваучер 500.00 | Капва се на количката, изгаря **цял** (без остатък), остатъкът прелива върху доставката, но не под 0 |
| `QAFREESHIP` | доставка, без таван | Доставката пада на 0 |
| `QASHIPCAP3` | доставка, таван 3.00 | Доставката пада с **най-много 3.00** |
| `QASHIPCAP0` | доставка, таван 0.00 | **Не сваля нищо.** `NULL` и `0.00` не са едно и също |
| `QAVOUCHER5` + `QAFREESHIP` | | Стакват се |
| `QAONESHOT` | ваучер 5.00, `max_uses=1` | За финализирането: след завършена поръчка `times_used` = 1, вторият опит дава `Кодът е изчерпан` |

### Кодове за финализиране

`QAONESHOT` е единственият с лимит. След цяла поръчка провери:

```sql
SELECT porach_suma, cendost, cendost_baza, pordost_coupon_discount
  FROM inmarta.porachki WHERE porachki_id = <ID>;
SELECT * FROM inmarta.order_promo_codes WHERE order_id = <ID>;
SELECT * FROM imartap.order_promo_codes WHERE order_id = <ID>;
SELECT COUNT(*) FROM inmarta.cart_promo_codes WHERE cart_id = <CART>;  -- 0
SELECT code, times_used FROM imartap.promo_codes WHERE created_by = 'qa-seed';
SELECT cat_no, it_cena, it_suma, it_cena_new, it_suma_new, discount_applied
  FROM inmarta.item WHERE porach_id = <ID>;
```

Инвариантът: `cendost = MAX(0, cendost_baza − pordost_coupon_discount)`.

> `inmarta.order_promo_codes` и `imartap.order_promo_codes` бяха **по 0 реда** преди
> това тестване. Нито една завършена поръчка с промо код не е минавала през тази среда —
> целият redemption път е без реално изпълнение.

---

## Две неща, които seed-ът чисти

Двата реда се трият, защото пречат на тестването, не защото са грешка в данните:

- **`SHIPPCT50`** — тип `shipping_percent`. Типът е премахнат изцяло (20.09.2026):
  махнат от DB ENUM-а на 21.08 и от PHP на 20.09. Стари dev бази още го приемат,
  докато не мине `database/migrations/deploy/16` + `17`.
- **`VOUCHER500ALL`** — `site='bg'` с `currency='ALL'`. Остатък от конверсионния слой,
  махнат на 10.09. Нарушава инварианта „един регион = една валута".

Останалите пет `fresh-seed` кода (`PERCENT10`, `VOUCHER5`, `COUPON5`, `FREESHIP`,
`SHIPCAP3`) не се пипат — те са примерният набор за чиста инсталация.

---

## Прихващане на имейлите

`lamp-php84` няма MTA — `mail()` не праща нищо и не пише никъде. За да се
провери писмото за потвърждение, сложи шим:

```bash
docker exec lamp-php84 sh -c 'cat > /usr/sbin/sendmail <<"EOF"
#!/bin/sh
mkdir -p /tmp/qa-mail
cat > "/tmp/qa-mail/$(date +%s%N).eml"
exit 0
EOF
chmod +x /usr/sbin/sendmail; mkdir -p /tmp/qa-mail; chmod 777 /tmp/qa-mail'
```

Apache върви като `www-data`, затова директорията трябва да е 777. След поръчка:
`docker exec lamp-php84 ls /tmp/qa-mail/`. Шимът живее само докато контейнерът е
вдигнат.

## Миграции, нужни преди тестването

`database/migrations/deploy/13-add-cendost-baza.sql` не е пуснат на dev дъмпа.
Без него `cendost_baza` липсва и стъпка 3 / финализирането не могат да се минат:

```bash
docker exec -i lamp-mysql8 mysql -uroot -ptiger -D inmarta < database/migrations/deploy/13-add-cendost-baza.sql
docker exec lamp-mysql8 mysql -uroot -ptiger -e \
  "ALTER TABLE imartap.porachki ADD COLUMN cendost_baza DECIMAL(10,2) NULL DEFAULT NULL;"
```

## Известни проблеми, които ще срещнеш

Не ги докладвай като нови:

1. ~~**Percent отстъпката липсва в имейла.**~~ Фикснато на 20.09.2026 —
   `podavam_za.php` чете `COALESCE(NULLIF(it_cena_new,0), it_cena)`.
2. **Паднал код на стъпка 3 не казва нищо.** Банерът за автоматично премахнат код е само
   в `case.php:233-250`. `case_potv.php` вика същия `promo_recalc()`, но не рендира
   `dropped_codes`.
3. **Заглавието над полето казва `produktnomerzaemail`.** `promo-input.php:38` чете
   `$prevodite[3100]`, а ред 3100 вече е зает с друга стойност, така че `??` fallback-ът
   не гръмва. Редове 3101–3107 липсват в дъмпа и падат на fallback правилно.

4. **Празна страница „Благодарим за поръчката".** `podavam_za.php:1877` слага
   бисквитката `mart_podzav1` с номера на поръчката, но `the-marketer/utils/v2/set-email.php:42`
   вече е ехнал `<script>` → `Cannot modify header information`. При
   `output_buffering = 0` (както е в `lamp-php84`) бисквитката не се слага и
   `/potvardih-porachkata` не показва поръчката. Не е промо бъг.

5. **Поръчка под минимума минава.** Проверката „Минимална сума за поръчка 5 лв."
   е само в изгледа на количката. Ваучер, който свали сметката под прага, не спира
   финализирането — поръчка 421631 завърши с `porach_suma = 4.00`.
