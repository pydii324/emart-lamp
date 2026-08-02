# Usages of `it_cena_baza` and `it_suma_baza`

Generated: 2026-06-29. Search scope: whole repo (excluding `.git`). Total raw matches: **171** (none in `emart-monorepo`).

These two columns exist on tables `item`, `item_l`, `item_no` (Phase-1 frozen pre-promo unit price / line total). Written by the cart writers (`v_case*.php`), read by `CartItems.php` and copied by `podavam_za.php`. Migrations `new/13` and `old/21` later **rename** them to `it_cena` / `it_suma`.

---

## PHP — application code & DB queries

### public_html/citte/v_case.php
Cart writer — `UPDATE ... SET it_cena_baza / it_suma_baza`.

| Line | Column |
|------|--------|
| 290 | `it_cena_baza = '" . $kolichka_ce . "'` |
| 291 | `it_suma_baza = '" . $suma_pol . "'` |
| 317 | `it_cena_baza = '" . $kolichka_ce . "'` |
| 318 | `it_suma_baza = '" . $suma_pol . "'` |

### public_html/citte/v_casekuk.php
Cart writer — `UPDATE ... SET`.

| Line | Column |
|------|--------|
| 225 | `it_cena_baza = '".$kolichka_ce."'` |
| 226 | `it_suma_baza = '".$suma_pol."'` |
| 253 | `it_cena_baza = '".$kolichka_ce."'` |
| 254 | `it_suma_baza = '".$suma_pol."'` |

### public_html/citte/v_case_actl.php
Cart writer — `UPDATE ... SET`.

| Line | Column |
|------|--------|
| 121 | `it_cena_baza = '".$kolichka_ce."'` |
| 122 | `it_suma_baza = '".$suma_pol."'` |
| 145 | `it_cena_baza = '".$kolichka_ce."'` |
| 146 | `it_suma_baza = '".$suma_pol."'` |

### public_html/citte/v_case_actli.php
Cart writer — `UPDATE ... SET`.

| Line | Column |
|------|--------|
| 100 | `it_cena_baza = '".$kolichka_ce."'` |
| 101 | `it_suma_baza = '".$suma_pol."'` |
| 129 | `it_cena_baza = '".$kolichka_ce."'` |
| 130 | `it_suma_baza = '".$suma_pol."'` |

### public_html/citte/v_cases.php
Cart writer — `UPDATE ... SET`.

| Line | Column |
|------|--------|
| 143 | `it_cena_baza = '".$kolichka_ce."'` |
| 144 | `it_suma_baza = '".$suma_pol."'` |
| 171 | `it_cena_baza = '".$kolichka_ce."'` |
| 172 | `it_suma_baza = '".$suma_pol."'` |

### public_html/citte/podavam_za.php
Order-finalize copy logic — `INSERT INTO item (...)` column lists, matching `SELECT ... FROM item_l / item_no / item`, plus the `VALUES` rows that bind `$row['it_cena_baza']` / `$row['it_suma_baza']`.

| Line | Role |
|------|------|
| 194 | INSERT INTO item column list (from item_l) |
| 196 | SELECT ... FROM item_l |
| 223 | VALUES row — `$row['it_cena_baza']`, `$row['it_suma_baza']` |
| 240 | INSERT INTO item column list (from item) |
| 241 | SELECT ... FROM item |
| 247 | VALUES row — `$row['it_cena_baza']`, `$row['it_suma_baza']` |
| 912 | INSERT INTO item column list (from item_no) |
| 914 | SELECT ... FROM item_no |
| 941 | VALUES row — `$row['it_cena_baza']`, `$row['it_suma_baza']` |
| 957 | INSERT INTO item column list (from item) |
| 958 | SELECT ... FROM item |
| 964 | VALUES row — `$row['it_cena_baza']`, `$row['it_suma_baza']` |

### public_html/citte/lib/CartItems.php
Cart reader / subtotal logic.

| Line | Role |
|------|------|
| 10 | Doc comment (written by `v_case*.php`) |
| 26 | `@return` array shape doc (`it_suma_baza`) |
| 30 | `SELECT ... it_cena_baza, it_suma_baza` |
| 38 | PHP `$row['it_suma_baza'] !== null` check |
| 39 | `round((float)$row['it_suma_baza'], 2)` |
| 48 | output key `'it_suma_baza' => $phase1` |
| 55 | Doc comment (frozen `it_suma_baza`) |
| 58 | `SELECT COALESCE(SUM(COALESCE(it_suma_baza, it_suma + discount_applied)), 0)` |
| 81 | Comment (`it_suma_baza - discount_applied`) |

---

## SQL — migrations & docs (`mysql-dumps/`)

These are DDL/DML migrations and docs that create, populate, virtualize, verify, or rename the columns.

| File | Notes |
|------|-------|
| mysql-dumps/promo_codes/old/12-add-baza-columns.sql | Adds `it_cena_baza`/`it_suma_baza` to item_l, item_no, item + backfill (lines 3,8,11,13,27,28,33,34,41,42,47,48,55,56,61,62) |
| mysql-dumps/promo_codes/new/06-add-item-columns.sql | Adds the columns + backfill (lines 7,8,22,23,28,29,43,44,49,50,64,65,70,71) |
| mysql-dumps/promo_codes/old/20-virtualize-item-price-columns.sql | Virtual generated cols referencing baza cols (lines 4,10,11,12,16,18,50,57,64,84,91,98,118,125,132) |
| mysql-dumps/promo_codes/new/12-virtualize-item-price-columns.sql | Same as old/20 (lines 4,10,11,12,16,18,50,57,64,84,91,98,118,125,132) |
| mysql-dumps/promo_codes/new/11-verify-per-db.sql | Verify columns exist (line 12) |
| mysql-dumps/promo_codes/old/21-rename-item-price-columns.sql | CHANGE `it_cena_baza`→`it_cena`, `it_suma_baza`→`it_suma` (lines 9,10,27,35,61,63,68,70,115,117,122,124,169,171,176,178) |
| mysql-dumps/promo_codes/new/13-rename-item-price-columns.sql | Same rename as old/21 (lines 9,10,27,35,61,63,68,70,115,117,122,124,169,171,176,178) |
| mysql-dumps/promo_codes/migrations-github-comment.md | Docs reference |
| mysql-dumps/promo_codes/new/README.md | Docs reference |

---

## Summary

- **Writers** (set the columns): `v_case.php`, `v_casekuk.php`, `v_case_actl.php`, `v_case_actli.php`, `v_cases.php`.
- **Reader**: `lib/CartItems.php`.
- **Copy on order finalize**: `podavam_za.php` (item_l/item_no → item).
- **Schema lifecycle**: created by `06`/`old-12`, virtualized by `12`/`old-20`, renamed to `it_cena`/`it_suma` by `13`/`old-21`.

> After the rename migration (`new/13` / `old/21`) runs, the PHP cart writers/readers above still reference `it_cena_baza`/`it_suma_baza` and will break — those are the call sites to update.
