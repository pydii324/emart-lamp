# Тестови промо кодове (dev seed)

Източник: `public_html/citte/api/promo-validate-table.sql`

| Код | Type | Стойност | Min subtotal | Max uses | Бележка |
|---|---|---|---|---|---|
| **TEST10** | percent | 10% | — | ∞ | 10% отстъпка от subtotal |
| **SUMMER20** | percent | 20% | 50 лв | ∞ | 20% отстъпка при ≥ 50 лв subtotal |
| **FLAT5** | fixed | 5 лв | — | 10 | Ваучер 5 лв (`voucher_remainer = 50.00` лв общ budget → ~10 използвания) |
| **FREESHIP** | shipping | — | — | ∞ | Безплатна доставка (без `shipping_cap` → покрива пълната доставка) |

## Къде са seed-нати

- `inmarta`, `iimarta`, `almarta` (per `promo-codes-master-plan.md` Step 9 + `promo-code-migration-log.md` Step 3).
- Същите кодове ще се добавят и на bg/gr/останалите бази, когато се мигрират.

## ВАЖНО

Тези 4 кода са маркирани `created_by = 'dev-seed'` и **трябва да се изтрият преди реален production traffic** на съответния сайт.
