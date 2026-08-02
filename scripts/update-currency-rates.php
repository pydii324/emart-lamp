#!/usr/bin/env php
<?php
/**
 * update-currency-rates.php — refresh FLOATING FX rates in imartap.currency_rates.
 *
 * Base currency is BGN. currency_rates.rate_to_bgn = how many BGN one unit of the
 * currency buys. lib/PromoCode.php reads it to convert promo money-fields from the
 * code's currency → BGN at the catalog read boundary.
 *
 * Only is_fixed = 0 rows are touched — BGN and EUR are legally fixed (irrevocable)
 * and are NEVER fetched or overwritten. Which currencies get refreshed is driven
 * by the floating rows already in the table, so adding a new floating currency is
 * a data change (INSERT a row), not a code change.
 *
 * Provider: BNB (Bulgarian National Bank) daily fixing XML — free, no key. Since
 * the euro adoption the feed is EUR-based (EUR is not listed — it IS the base):
 * per ROW, REVERSERATE = EUR for 1 unit of the currency, RATE = units per 1 EUR.
 * BGN is fixed to EUR at 1.95583, so rate_to_bgn = REVERSERATE * 1.95583. Swap
 * fetch_bnb_rates() for ECB/frankfurter to cover any currency BNB omits.
 *
 * Safe by design: on any provider/parse failure NOTHING is written (last values
 * kept). NOT web-reachable (lives outside public_html) + hard CLI guard.
 *
 * Usage:
 *   php scripts/update-currency-rates.php            # fetch + write
 *   php scripts/update-currency-rates.php --dry-run  # fetch + print, no write
 *
 * Cron (BNB publishes ~16:00 EET on business days):
 *   30 16 * * 1-5  php /path/to/scripts/update-currency-rates.php >> /path/to/custom_logs/currency-rates.log 2>&1
 */

if (PHP_SAPI !== 'cli') { http_response_code(404); exit(1); } // never over HTTP

const BNB_XML_URL = 'https://www.bnb.bg/Statistics/StExternalSector/StExchangeRates/StERForeignCurrencies/index.htm?download=xml&search=&lang=EN';

// Irrevocable BGN adoption rate (mirrors PromoCode::EUR_TO_BGN). The BNB feed is
// EUR-based, so BGN amounts are derived through this fixed factor.
const EUR_TO_BGN = 1.95583;

$dryRun = in_array('--dry-run', $argv, true);
$LOG    = __DIR__ . '/../custom_logs/currency-rates.log';

function logln(string $m): void {
    global $LOG;
    $line = '[' . date('Y-m-d H:i:s') . '] ' . $m;
    fwrite(STDOUT, $line . "\n");
    @file_put_contents($LOG, $line . "\n", FILE_APPEND);
}

// ── DB bootstrap: reuse the app's connection globals (imartap = $msql_*p) ──────
$baubau = true; // zamysql.php exits unless this is set
require __DIR__ . '/../public_html/citte/zamysql.php';
// mysqli_connect($host, $user, $pass, $db) — 2nd arg is the USERNAME (app convention).
$db = @mysqli_connect($msql_hostp, $msql_portp, $msql_passp, $msql_basap);
if (!$db) { logln('FATAL: cannot connect to imartap: ' . mysqli_connect_error()); exit(1); }
mysqli_query($db, "SET NAMES 'utf8mb4';");

// ── Which currencies to refresh (BNB-sourced floating rows only) ──────────────
// is_fixed = 0 AND source = 'bnb': this is the BNB job, so it only ever touches
// rows it owns. is_fixed rows (BGN/EUR) are legally fixed; source='manual' rows
// (e.g. ALL — BNB does not publish Albanian lek) are maintained by hand and must
// stay untouched even if BNB ever starts listing them (migration 17 §comment).
$targets = [];
$r = mysqli_query($db, "SELECT currency FROM currency_rates WHERE is_fixed = 0 AND source = 'bnb';");
if (!$r) { logln('FATAL: currency_rates unavailable: ' . mysqli_error($db)); exit(1); }
while ($row = mysqli_fetch_row($r)) $targets[] = strtoupper($row[0]);
if (!$targets) { logln('No floating currencies to update. Done.'); exit(0); }

// ── Fetch provider rates: [ISO code => rate_to_bgn] ───────────────────────────
$rates = fetch_bnb_rates();
if ($rates === null) { logln('WARN: provider fetch failed — keeping last values.'); exit(2); }

// ── Write (WHERE mirrors the target filter so a fixed/manual row is never hit) ─
$updated = 0; $missing = [];
foreach ($targets as $cur) {
    if (!isset($rates[$cur])) { $missing[] = $cur; continue; }
    $rateSql = number_format($rates[$cur], 8, '.', '');
    if ($dryRun) { logln(sprintf('DRY-RUN %s -> %s BGN', $cur, $rateSql)); $updated++; continue; }
    $curEsc = mysqli_real_escape_string($db, $cur);
    $ok = mysqli_query($db,
        "UPDATE currency_rates SET rate_to_bgn = '$rateSql', updated_at = NOW(), source = 'bnb'
          WHERE currency = '$curEsc' AND is_fixed = 0 AND source = 'bnb';");
    if ($ok) { $updated++; logln(sprintf('%s -> %s BGN', $cur, $rateSql)); }
    else       logln("ERROR updating $cur: " . mysqli_error($db));
}
if ($missing) logln('WARN: provider had no rate for: ' . implode(', ', $missing) . ' (left unchanged).');
logln(($dryRun ? 'DRY-RUN ' : '') . "Done. $updated currency(ies) processed.");
exit(0);

// ═════════════════════════════════════════════════════════════════════════════

/**
 * BNB daily fixing XML → [ISO code => rate_to_bgn].
 *
 * Post euro-adoption the feed is EUR-based (verified against the live feed
 * 2026-07-20): ROWSET > ROW, each with CODE, REVERSERATE (= EUR per 1 unit of
 * the currency) and RATE (= units per 1 EUR). EUR itself is not listed — it is
 * the base. BGN is fixed to EUR at 1.95583, so rate_to_bgn = REVERSERATE *
 * EUR_TO_BGN (fallback: (1 / RATE) * EUR_TO_BGN). The first ROW is a header
 * whose CODE is the literal "Code" — dropped by the 3-char guard.
 *
 * Returns null on network/parse failure so the caller keeps the last values.
 * Replace this single function to switch providers.
 */
function fetch_bnb_rates(): ?array {
    $xml = http_get(BNB_XML_URL);
    if ($xml === null) return null;
    $prev = libxml_use_internal_errors(true);
    $doc  = simplexml_load_string($xml);
    libxml_use_internal_errors($prev);
    if ($doc === false) { logln('ERROR: BNB XML parse failed.'); return null; }
    // BNB ROWSET/ROW, EUR-based (EUR itself is not listed — it is the base):
    //   REVERSERATE = EUR for 1 unit of the currency   (preferred)
    //   RATE        = units of the currency for 1 EUR   (fallback: 1/RATE)
    // BGN is fixed to EUR, so rate_to_bgn = (EUR per unit) * EUR_TO_BGN.
    $out = [];
    foreach ($doc->ROW as $row) {
        $code = strtoupper(trim((string)$row->CODE));
        if (strlen($code) !== 3) continue; // skip GOLD / header / blank rows
        $eurPerUnit = (float)str_replace(',', '.', (string)$row->REVERSERATE);
        if ($eurPerUnit <= 0) {
            $unitsPerEur = (float)str_replace(',', '.', (string)$row->RATE);
            if ($unitsPerEur > 0) $eurPerUnit = 1.0 / $unitsPerEur;
        }
        if ($eurPerUnit <= 0) continue;
        $out[$code] = round($eurPerUnit * EUR_TO_BGN, 8);
    }
    return $out ?: null;
}

/** GET with a short timeout (curl if present, else file_get_contents). Null on failure. */
function http_get(string $url): ?string {
    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => 15,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_USERAGENT      => 'emart-currency-updater/1.0',
        ]);
        $body = curl_exec($ch);
        $err  = curl_error($ch);
        $http = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        // curl_close() is a deprecated no-op since PHP 8.0 — the handle frees on unset/GC.
        if ($body === false || $http >= 400) { logln("ERROR: HTTP fetch failed ($http) $err"); return null; }
        return (string)$body;
    }
    $ctx  = stream_context_create(['http' => ['timeout' => 15, 'user_agent' => 'emart-currency-updater/1.0']]);
    $body = @file_get_contents($url, false, $ctx);
    return $body === false ? null : $body;
}
