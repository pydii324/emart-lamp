# Promo code migration log — Albania (`almarta`)

> Audit trail на всяка стъпка от прилагането на новата promo-codes schema върху `al` (Server 3, host `188.245.82.152`, DB `almarta`).
> Append-only. Не редактираме историята — само добавяме нови записи.
>
> Свързано: `promo-codes-master-plan.md`, `promo-codes-execution-log.md` (Steps 0–9 за `imartap` + `inmarta` + `iimarta`).
> Изпълнение: `emart-monorepo/packages/db/scripts/batch-sql-dbs/sql-batch-dbs.ts`.

Формат на всяка стъпка:

```
## YYYY-MM-DD HH:MM — Step N: <заглавие>
**Какво направено:** ...
**Команда / SQL:** ...
**Резултат / output:** ...
**Файлове засегнати:** ...
**Бележки:** ...
```

---

## 2026-05-19 — Step 0: Планиране и контекст

**Какво направено:**
- Прегледани последни commits в `public_html/` (5 promo-related: `2212156`, `1ae6ae8`, `043700e`, `df315c5`, `6b5c2ca`).
- Прегледани `promo-codes-master-plan.md` и `promo-codes-execution-log.md` (Steps 0–9).
- Идентифициран DDL източник: `public_html/citte/api/promo-validate-table.sql` (3 таблици + 4 dev-seed кода).
- Идентифициран executor: `emart-monorepo/packages/db/scripts/batch-sql-dbs/sql-batch-dbs.ts` (split на `;`, чете `./query.sql`, итерира по domains от args).
- Потвърдено: `.env` има `DATABASE_URL_al` попълнен (host `188.245.82.152`, user `ivo`, db `almarta`).

**Плановите стъпки:**
1. Pre-flight (read-only) — SHOW TABLES / SHOW COLUMNS / COUNT(*) върху `almarta`.
2. Решение: DROP+recreate (ако стара schema) vs no-op (ако нова) vs fresh CREATE (ако таблиците липсват).
3. Финален `query.sql` (евентуални DROP-ове + DDL от `promo-validate-table.sql`).
4. Изпълнение: `bun sql-batch-dbs.ts "al" true`.
5. Post-verification (SHOW CREATE, COUNT, sample SELECT).

**Файлове засегнати:** няма (само планиране).

**Бележки:**
- Това е production DB на Server 3 — pre-flight (Step 1) е задължителен.
- Спираме преди destructive action ако има реални данни.

---

## 2026-05-19 — Step 1: Pre-flight (read-only) срещу `almarta`

**Какво направено:**
- `bun install` в monorepo root (dependencies липсваха).
- Изпълнен read-only `query.sql` с INFORMATION_SCHEMA queries (не гърмят при липсващи таблици).
- Sanity check: `SELECT DATABASE(), @@hostname, VERSION()` + `SHOW TABLES`.

**Команда:**
```bash
cd emart-monorepo/packages/db/scripts/batch-sql-dbs
bun sql-batch-dbs.ts "al" true
```

**Резултат:**
- Connected: `almarta` на `db2.em-art.email`, MySQL `8.0.45-0ubuntu0.24.04.1` (= Server 3 `188.245.82.152`).
- `promo_codes`, `cart_promo_codes`, `order_promo_codes`: **не съществуват** (всички 4 INFORMATION_SCHEMA queries върнаха `[]`).
- DB има реален e-commerce schema (catalog 100k+ реда, klienti 91k, etc.) — потвърдено че сме на правилната production DB.

**Файлове засегнати:**
- `emart-monorepo/packages/db/scripts/batch-sql-dbs/query.sql` (working file — read-only pre-flight queries).
- Repo root `bun.lock` обновен от `bun install`.

**Решение:**
- → Fresh CREATE (без DROP). Без data loss риск.
- DDL източник: `public_html/citte/api/promo-validate-table.sql` (3 таблици + 4 dev seed кода, същите като в inmarta/iimarta per Step 9).

---

## 2026-05-19 — Step 2: Bug fix в `sql-batch-dbs.ts` (line-comment safe split)

**Какво направено:**
- Открит bug: `query.split(";")` чупи DDL когато `--` коментари съдържат `;`. Конкретно `promo-validate-table.sql` редове 17 и 18:
  ```
  `max_uses` INT NOT NULL DEFAULT 0,  -- 0 = безлимитно (общо); 1 = single-use
  `times_used` INT NOT NULL DEFAULT 0,  -- брояч; ++ при markUsed()
  ```
  Това би разрязало CREATE TABLE на 3 невалидни chunks → `promo_codes` нямаше да се създаде → FK в `cart_promo_codes` щеше да fail-не каскадно.
- Фикс: strip `--` line comments **преди** split на `;`.

**SQL/Code промяна:**
```ts
const queries = readFileSync(join(import.meta.dir, "query.sql"), "utf-8")
  .split("\n")
  .map((line) => line.replace(/--.*$/, ""))
  .join("\n")
  .split(";")
  .map((s) => s.trim())
  .filter(Boolean);
```

**Файлове засегнати:**
- `emart-monorepo/packages/db/scripts/batch-sql-dbs/sql-batch-dbs.ts`

**Бележки:**
- Не handles `/* ... */` block comments — не са нужни за този DDL. Ако в бъдеще се появят, ще се добави регекс.
- Не handles `;` в string literals — но in this DDL и в типична DDL употреба няма.
- inmarta/iimarta (Step 9) са били изпълнени с друг tooling (вероятно `mysql` CLI директно), затова бъга не е изскочил тогава.

---

## 2026-05-19 — Step 3: Execute DDL срещу `almarta`

**Какво направено:**
- `query.sql` ← `cp public_html/citte/api/promo-validate-table.sql` (idempotent DDL с `CREATE TABLE IF NOT EXISTS` + INSERT IGNORE).
- Изпълнено срещу `al`.

**Команда:**
```bash
cd emart-monorepo/packages/db/scripts/batch-sql-dbs
bun sql-batch-dbs.ts "al" true
```

**Резултат (5 statement-а, всичките успешни):**
| # | Statement | affectedRows | Бележка |
|---|---|---|---|
| 1 | `CREATE TABLE promo_codes` | 0 | OK |
| 2 | `CREATE TABLE cart_promo_codes` | 0 | OK (FK към promo_codes резолвиран) |
| 3 | `CREATE TABLE order_promo_codes` | 0 | OK (FK към promo_codes резолвиран) |
| 4 | `INSERT INTO promo_codes ... VALUES (4 rows)` | 4 | Records: 4, Duplicates: 0, Warnings: 0 |
| 5 | `UPDATE promo_codes SET voucher_remainer=50 WHERE code='FLAT5'` | 1 | matched: 1, changed: 1 |

**Файлове засегнати:**
- DB `almarta`: създадени `promo_codes`, `cart_promo_codes`, `order_promo_codes`; seed-нати 4 dev кода.
- `emart-monorepo/packages/db/scripts/batch-sql-dbs/query.sql` — working file (текущо съдържание = post-verification queries).

---

## 2026-05-19 — Step 4: Post-verification

**Какво направено:**
- `query.sql` ← INFORMATION_SCHEMA queries за schema + FK + sample SELECT от promo_codes.
- Изпълнено срещу `al`.

**Резултат:**

**Tables (InnoDB, utf8mb4_unicode_ci):** `cart_promo_codes`, `order_promo_codes`, `promo_codes` ✓

**`promo_codes` колони (всичките 17 нови):**
- `id` int PK, `code` varchar(50) UNIQUE, `type` ENUM('percent','fixed','shipping') default 'percent'
- `discount_value` decimal(10,2), `voucher_remainer` decimal(10,2) NULL ✓ (новата колона)
- `min_subtotal` decimal(10,2) default 0, `shipping_cap` decimal(10,2) NULL
- `max_uses` int default 0, `times_used` int default 0
- `active` tinyint(1) default 1 (key MUL за `idx_active_exp`), `stack_group` tinyint NULL
- `expiration_date`, `created_at`, `used_at` — всички **varchar(14)** ✓ (както master plan, NOT TIMESTAMP)
- `source` ENUM('the-marketer','manual','bulk-import') default 'manual'
- `note` varchar(255), `site` varchar(10), `created_by` varchar(255)

**`cart_promo_codes`:** `created_at` = **varchar(14) NOT NULL** ✓ (не TIMESTAMP), FK `fk_cpc_promo` → `promo_codes(id)` ✓

**`order_promo_codes`:** `created_at` = **varchar(14) NOT NULL** ✓, FK `fk_opc_promo` → `promo_codes(id)` ✓

**Seed данни в `promo_codes`:**
| id | code | type | discount_value | voucher_remainer | max_uses | active |
|---|---|---|---|---|---|---|
| 1 | TEST10 | percent | 10.00 | NULL | 0 | 1 |
| 2 | SUMMER20 | percent | 20.00 | NULL | 0 | 1 |
| 3 | FLAT5 | fixed | 5.00 | **50.00** | 10 | 1 |
| 4 | FREESHIP | shipping | 0.00 | NULL | 0 | 1 |

FLAT5 `voucher_remainer = 50.00` ✓ (UPDATE-нат от Step 3.5).

**Файлове засегнати:** няма (само read).

**Бележки:**
- Schema на `almarta.promo_codes` 1:1 с `inmarta.promo_codes` / `iimarta.promo_codes` (per Step 9 of `promo-codes-execution-log.md`).
- Production миграция приключена. Albania cart flow вече може да чете/пише promo codes без `Unknown column 'voucher_remainer'` грешката.

---

## Резюме

| Стъпка | Резултат |
|---|---|
| 0. Планиране | ✓ |
| 1. Pre-flight | ✓ (no tables → fresh CREATE) |
| 2. Bug fix в batch script | ✓ (line-comment safe split) |
| 3. Execute DDL | ✓ (3 tables + 4 seed) |
| 4. Post-verification | ✓ (schema + FK + data всичко OK) |

**Производствено състояние:** `almarta` сега има същата promo schema като `inmarta`/`iimarta`. Готова за PHP cart flow.

**Следващи стъпки (извън scope на тази миграция):**
- Изтриване на dev seed кодовете (TEST10/SUMMER20/FLAT5/FREESHIP) преди реален production traffic.
- Прилагане на същия DDL върху останалите per-site DBs където промо-кодовете ще се ползват (per Step 9 списък — bg, gr вече са; всички други по нужда).
- End-to-end test на cart flow срещу AL site.

Готово. Миграцията е приключена и изцяло логната в promo-code-migration-log.md.

  Какво стана

  Step 1 — Pre-flight: almarta (host db2.em-art.email = Server 3) нямаше нито една от трите промо таблици →
  fresh CREATE без риск.

  Step 2 — Bug fix: Открих че sql-batch-dbs.ts чупи DDL когато -- коментари съдържат ; (редове 17/18 на
  promo-validate-table.sql). Добавих strip на line-comments преди split.

  Step 3 — DDL execute: 3 CREATE TABLE + 4 INSERT seed + 1 UPDATE на FLAT5. Всичките 5 statement-а минаха.

  Step 4 — Verification: Schema 1:1 с inmarta/iimarta (voucher_remainer, created_at varchar(14), FK-ите
  правилни, ENUM-и правилни). Seed данните проверени.

  Засегнати файлове

  - promo-code-migration-log.md — нов, пълен audit trail
  - emart-monorepo/packages/db/scripts/batch-sql-dbs/sql-batch-dbs.ts — bug fix (split comment safety)
  - emart-monorepo/packages/db/scripts/batch-sql-dbs/query.sql — working file (текущо съдържа
  post-verification queries)
  - Repo bun.lock — обновен от bun install
  - DB almarta: новосъздадени promo_codes, cart_promo_codes, order_promo_codes

  Извън scope (за после)

  - Изтриване на dev seed кодовете преди реален AL traffic.
  - Същата миграция на останалите per-site DBs (Step 9 от стария log покрива bg+gr).


  Step 3 — DDL execute: 3 CREATE TABLE + 4 INSERT seed + 1 UPDATE на FLAT5. Всичките 5 statement-а минаха.

  Step 4 — Verification: Schema 1:1 с inmarta/iimarta (voucher_remainer, created_at varchar(14), FK-ите
  правилни, ENUM-и правилни). Seed данните проверени.

  Засегнати файлове

  - promo-code-migration-log.md — нов, пълен audit trail
  - emart-monorepo/packages/db/scripts/batch-sql-dbs/sql-batch-dbs.ts — bug fix (split comment safety)
  - emart-monorepo/packages/db/scripts/batch-sql-dbs/query.sql — working file (текущо съдържа
  post-verification queries)
  - Repo bun.lock — обновен от bun install
  - DB almarta: новосъздадени promo_codes, cart_promo_codes, order_promo_codes

  Извън scope (за после)

  - Изтриване на dev seed кодовете преди реален AL traffic.
  - Същата миграция на останалите per-site DBs (Step 9 от стария log покрива bg+gr).