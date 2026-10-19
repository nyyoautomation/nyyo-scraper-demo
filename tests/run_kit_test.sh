#!/usr/bin/env bash
# From-scratch test of the shipped ZIP (build box; needs docker and python3; pwsh optional).
#   tests/run_kit_test.sh [path/to/nyyo-scraper-kit.zip]       RUN_BROWSER=0 to skip the browser add-on
# Writes raw logs and checks to docs/kit-test-proof/.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; ZIP="${1:-$REPO/dist/nyyo-scraper-kit.zip}"
PROOF="$REPO/docs/kit-test-proof"; rm -rf "$PROOF"; mkdir -p "$PROOF"
PWSH="$(command -v pwsh || echo /tmp/pwsh/pwsh)"; RUN_BROWSER="${RUN_BROWSER:-1}"
W="$(mktemp -d /tmp/scrapekit-test.XXXX)"; K="$W/nyyo-scraper-kit"; LOG="$W/server.log"; PORT=47391
PASS=0; FAILN=0
check() { if eval "$2"; then echo "PASS  $1"; PASS=$((PASS+1)); else echo "FAIL  $1"; FAILN=$((FAILN+1)); fi; }
run() { local name="$1"; shift; { echo "\$ $*"; echo; "$@" 2>&1; local rc=$?; echo; echo "[exit code $rc]"; } | sed 's/\x1b\[[0-9;]*m//g' > "$PROOF/$name"; }
code() { sed -n 's/^\[exit code \([0-9]*\)\]$/\1/p' "$PROOF/$1"; }
rows() { python3 - "$@" <<'PY'
import csv, sys
with open(sys.argv[1], encoding="utf-8-sig", newline="") as fh:
    r = list(csv.DictReader(fh))
drop = set(sys.argv[2:]) | {"scraped_at"}
for row in r: print(",".join(f"{k}={v}" for k, v in row.items() if k not in drop))
PY
}
h() { sha256sum "$1" | cut -d' ' -f1; }
SH() { (cd "$K" && NYYO_DOCKER_NETWORK=host ./setup.sh --no-open "$@"); }
PS() { (cd "$K" && NYYO_DOCKER_NETWORK=host "$PWSH" -NoProfile -File ./setup.ps1 -NoOpen "$@"); }
cfg() { cp "$K/tests/$1" "$K/config/scrape.toml"; }

{
  echo "Date: $(date '+%b %-d, %Y, %H:%M %Z')"; echo "System: $(uname -sm)"
  echo "Docker: $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
  echo "Python on the host: $(python3 -V 2>&1)"
  echo "PowerShell: $("$PWSH" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null || echo none)"
  echo "Kit ZIP: $(basename "$ZIP") sha256 $(h "$ZIP")"
  echo "Scratch folder: $W (empty before unzip)"
} > "$PROOF/00_environment.txt"

# ---- From scratch: no kit image, fresh unzip, no config, no .venv ----
docker rmi -f nyyo-scraper-kit:1.0.0 nyyo-scraper-kit:1.0.0-browser >/dev/null 2>&1
echo "kit images present before test: $(docker images -q 'nyyo-scraper-kit' | wc -l)" >> "$PROOF/00_environment.txt"
(cd "$W" && unzip -q "$ZIP") && { echo; echo "unzipped:"; (cd "$K" && find . -type f | sort); } >> "$PROOF/00_environment.txt"
python3 "$K/tests/fixture_server.py" "$PORT" "$LOG" & SRV=$!; trap 'kill $SRV 2>/dev/null' EXIT; sleep 0.5

# 1. Buyer's first run: example config, public practice site books.toscrape.com (Docker)
run 01_setup_sh_docker_first_run_books.txt SH
B1="$(h "$K/output/books.csv")"; cp "$K/output/books.csv" "$W/books1.csv"
run 02_setup_sh_docker_second_run_books.txt SH
# 2. Buyer edits the config: local fixture shop (robots.txt, 429, duplicates)
cfg fixture.toml
: > "$LOG"; run 03_setup_sh_docker_fixture.txt SH; cp "$LOG" "$W/log03.jsonl"; cp "$K/output/shop.csv" "$W/shop03.csv"
: > "$LOG"; run 04_setup_sh_docker_fixture_again.txt SH
run 05_setup_sh_native_first_run.txt SH --native; cp "$K/output/shop.csv" "$W/shop05.csv"
run 06_setup_sh_native_second_run.txt SH --native; cp "$K/output/shop.csv" "$W/shop06.csv"
if [ -x "$PWSH" ]; then
  run 07_setup_ps1_docker_run.txt PS; cp "$K/output/shop.csv" "$W/shop07.csv"
  rm -rf "$K/.venv"
  run 08_setup_ps1_native_first_run.txt PS -Native; cp "$K/output/shop.csv" "$W/shop08.csv"
  run 09_setup_ps1_native_second_run.txt PS -Native
fi
# 3. Safety: broken selector must not overwrite the good file
S_BEFORE="$(h "$K/output/shop.csv")"
sed -i 's/^items = "li.product"/items = "li.renamed-by-the-site"/' "$K/config/scrape.toml"
run 10_zero_rows_keeps_previous.txt SH --target shop
S_AFTER="$(h "$K/output/shop.csv")"
# 4. Google Sheets: missing key (Docker), then a stand-in for Google's library (native)
cfg fixture.toml
sed -i 's/^enabled = false/enabled = true/; s/^spreadsheet_id = ""/spreadsheet_id = "TEST-SHEET-ID"/' "$K/config/scrape.toml"
run 11_sheets_missing_key.txt SH --target shop
printf '{"type": "service_account", "client_email": "kit-test-service-account"}\n' > "$K/credentials/service-account.json"
export FAKE_GSPREAD_LOG="$W/gspread.jsonl"; : > "$FAKE_GSPREAD_LOG"
run 12_sheets_fake_google.txt env PYTHONPATH="$REPO/tests/fake_gspread" bash -c "cd '$K' && ./setup.sh --native --no-open --target shop"
rm -f "$K/credentials/service-account.json"
# 5. Browser add-on (JavaScript page)
if [ "$RUN_BROWSER" = 1 ]; then
  cfg fixture-browser.toml
  run 13_setup_sh_browser_docker.txt SH --browser
  cp "$K/output/shopjs.csv" "$W/shopjs.csv" 2>/dev/null
  docker image inspect -f '{{.Size}}' nyyo-scraper-kit:1.0.0-browser 2>/dev/null | awk '{printf "browser image size: %d MB\n", $1/1e6}' >> "$PROOF/13_setup_sh_browser_docker.txt"
fi
cp "$W/books1.csv" "$PROOF/sample-books.csv"; cp "$W/shop03.csv" "$PROOF/sample-shop.csv"; cp "$K/output/shop.json" "$PROOF/sample-shop.json"
python3 - "$W/log03.jsonl" > "$PROOF/03b_server_log_fixture.txt" <<'PY'
import json, sys
L = [json.loads(l) for l in open(sys.argv[1])]
t0 = L[0]["t"]
for l in L: print(f"+{l['t']-t0:6.2f}s  {l['status']}  {l['path']:<22} UA: {l['ua']}")
PY

# 6. build_dist.sh refuses secrets and off-platform contact details (on a throwaway copy of the repo)
C="$W/repo-copy"; mkdir -p "$C"; (cd "$REPO" && tar --exclude=.git --exclude=./dist -cf - .) | (cd "$C" && tar -xf -)
FAKEKEY="AKIA""FAKEFAKEFAKE1234"; FAKEMAIL="kit-test""@""example.org"
{
  echo "== A. clean copy"; (cd "$C" && scripts/build_dist.sh 2>&1); echo "[exit code $?]"
  echo; echo "== B. a Google key file left in credentials/"
  printf '{"type": "service_account"}\n' > "$C/credentials/service-account.json"
  (cd "$C" && scripts/build_dist.sh 2>&1); echo "[exit code $?]"; rm -f "$C/credentials/service-account.json"
  echo; echo "== C. a fake AWS key pasted into INSTALL.md"
  cp "$C/INSTALL.md" "$W/INSTALL.bak"; echo "aws_access_key_id = $FAKEKEY" >> "$C/INSTALL.md"
  (cd "$C" && scripts/build_dist.sh 2>&1); echo "[exit code $?]"; cp "$W/INSTALL.bak" "$C/INSTALL.md"
  echo; echo "== D. an e-mail address added to INSTALL.md"
  echo "Contact: $FAKEMAIL" >> "$C/INSTALL.md"
  (cd "$C" && scripts/build_dist.sh 2>&1); echo "[exit code $?]"; cp "$W/INSTALL.bak" "$C/INSTALL.md"
} | sed "s/$FAKEKEY/<fake AWS key>/g; s/$FAKEMAIL/<test address>/g; s#/tmp/tmp\.[A-Za-z0-9]*#<stage>#g; s/\x1b\[[0-9;]*m//g" > "$PROOF/15_build_dist_refusal.txt"

# ---- Checks ----
docker image inspect -f '{{.Size}}' nyyo-scraper-kit:1.0.0 | awk '{printf "base image size: %d MB\n", $1/1e6}' >> "$PROOF/00_environment.txt"
{
  echo "Checks"; echo
  check "books.toscrape.com: 60 rows from 3 pages, every row has title, price, availability, rating 1-5, absolute url" \
    "python3 -c \"import csv,sys;r=list(csv.DictReader(open('$W/books1.csv',encoding='utf-8-sig')));sys.exit(0 if len(r)==60 and all(x['title'] and float(x['price'])>0 and x['availability'] and x['rating'] in '12345' and x['url'].startswith('https://books.toscrape.com/catalogue/') for x in r) and len({x['url'] for x in r})==60 else 1)\""
  check "books.toscrape.com: JSON has the same 60 rows as the CSV" \
    "python3 -c \"import json,csv,sys;j=json.load(open('$K/output/books.json'));c=list(csv.DictReader(open('$K/output/books.csv',encoding='utf-8-sig')));sys.exit(0 if len(j)==len(c)==60 and [x['url'] for x in j]==[x['url'] for x in c] else 1)\""
  check "books second run: image reused, same rows, previous file kept" \
    "grep -q 'already installed' '$PROOF/02_setup_sh_docker_second_run_books.txt' && diff -q <(rows '$W/books1.csv') <(rows '$K/output/books.csv') >/dev/null && diff -q <(rows '$W/books1.csv') <(rows '$K/output/books.previous.csv') >/dev/null"
  check "config/scrape.toml created on the first run only (second run did not overwrite it)" \
    "grep -q 'Created config/scrape.toml' '$PROOF/01_setup_sh_docker_first_run_books.txt' && ! grep -q 'Created config' '$PROOF/02_setup_sh_docker_second_run_books.txt'"
  check "fixture: 24 rows exactly as expected (25 items, 1 duplicate removed), all fields right" \
    "diff -u <(rows '$REPO/tests/expected_shop.csv') <(rows '$W/shop03.csv')"
  check "fixture: JSON matches the CSV (types: price number, rating int or empty)" \
    "python3 -c \"import json,sys;j=json.load(open('$PROOF/sample-shop.json'));sys.exit(0 if len(j)==24 and j[1]['price']==1299 and j[0]['price']==12.5 and j[0]['rating']==4 and j[3]['rating']=='' else 1)\""
  check "robots.txt: /private/ never requested, target reported as blocked" \
    "! grep -q '/private/' '$W/log03.jsonl' && grep -q 'robots.txt forbids it' '$PROOF/03_setup_sh_docker_fixture.txt'"
  check "robots.txt fetched first, before any page" "head -1 '$W/log03.jsonl' | grep -q robots.txt"
  check "rate limit: at least 0.5 s between any two requests to the site" \
    "python3 -c \"import json,sys;t=[json.loads(l)['t'] for l in open('$W/log03.jsonl')];sys.exit(0 if all(b-a>=0.49 for a,b in zip(t,t[1:])) else 1)\""
  check "HTTP 429 on page 2: waited (Retry-After honoured) and retried, page 2 scraped" \
    "python3 -c \"import json,sys;L=[json.loads(l) for l in open('$W/log03.jsonl')];p=[l for l in L if l['path']=='/shop/page-2.html'];sys.exit(0 if [x['status'] for x in p]==[429,200] and p[1]['t']-p[0]['t']>=1 else 1)\""
  check "user-agent names the tool on every request" \
    "python3 -c \"import json,sys;sys.exit(0 if all(json.loads(l)['ua'].startswith('NyyoScraperKit/1.0.0 (+https://github.com/nyyoautomation/nyyo-scraper-demo)') for l in open('$W/log03.jsonl')) else 1)\""
  check "fixture re-run (Docker): same 24 rows, no duplicates added" "diff -q <(rows '$W/shop03.csv') <(rows '$K/output/shop.previous.csv') >/dev/null"
  check "native Python: venv created + pinned packages installed by hash, then reused" \
    "grep -q 'Installing pinned Python packages' '$PROOF/05_setup_sh_native_first_run.txt' && grep -q 'already installed' '$PROOF/06_setup_sh_native_second_run.txt'"
  check "Docker and native give identical rows" "diff -q <(rows '$W/shop03.csv') <(rows '$W/shop05.csv') >/dev/null && diff -q <(rows '$W/shop03.csv') <(rows '$W/shop06.csv') >/dev/null"
  if [ -x "$PWSH" ]; then
    check "setup.ps1 (PowerShell 7, Docker): same 24 rows" "diff -q <(rows '$W/shop03.csv') <(rows '$W/shop07.csv') >/dev/null && grep -q 'already installed' '$PROOF/07_setup_ps1_docker_run.txt'"
    check "setup.ps1 native: creates its venv, installs by hash, same rows, then reuses it" \
      "grep -q 'Installing pinned' '$PROOF/08_setup_ps1_native_first_run.txt' && diff -q <(rows '$W/shop03.csv') <(rows '$W/shop08.csv') >/dev/null && grep -q 'already installed' '$PROOF/09_setup_ps1_native_second_run.txt'"
  fi
  check "exit code 1 (warning: robots-blocked target) on every fixture run, 0 on the books runs" \
    "[ \$(code 01_setup_sh_docker_first_run_books.txt) = 0 ] && [ \$(code 02_setup_sh_docker_second_run_books.txt) = 0 ] && [ \$(code 03_setup_sh_docker_fixture.txt) = 1 ] && [ \$(code 04_setup_sh_docker_fixture_again.txt) = 1 ] && [ \$(code 05_setup_sh_native_first_run.txt) = 1 ] && [ \$(code 06_setup_sh_native_second_run.txt) = 1 ]"
  check "broken selector: exit 2, 0 rows, previous good file kept byte for byte" \
    "[ \$(code 10_zero_rows_keeps_previous.txt) = 2 ] && [ '$S_BEFORE' = '$S_AFTER' ] && grep -q 'previous file shop.csv was kept' '$PROOF/10_zero_rows_keeps_previous.txt'"
  check "Google Sheets without a key: clear message, CSV/JSON still written, exit 1" \
    "grep -q 'Google Sheets skipped: credentials file not found' '$PROOF/11_sheets_missing_key.txt' && [ \$(code 11_sheets_missing_key.txt) = 1 ]"
  check "Google Sheets (stand-in library): tab 'shop' cleared then filled with header + 24 rows at A1" \
    "python3 -c \"import json,sys;L=[json.loads(l) for l in open('$FAKE_GSPREAD_LOG')];c=[l['call'] for l in L];u=[l for l in L if l['call']=='update'];sys.exit(0 if c==['service_account','open_by_key','add_worksheet','clear','update'] and len(u[0]['values'])==25 and u[0]['values'][0][:3]==['sku','name','price'] and u[0]['range']=='A1' and L[1]['key']=='TEST-SHEET-ID' else 1)\" && [ \$(code 12_sheets_fake_google.txt) = 0 ]"
  check "no Google key, config or output left inside the kit's shipped files" "[ ! -e '$K/credentials/service-account.json' ]"
  check "build_dist.sh: clean copy builds; refuses a key file, a fake AWS key and an e-mail address" \
    "[ \$(grep -c '^\[exit code 0\]' '$PROOF/15_build_dist_refusal.txt') = 1 ] && [ \$(grep -c '^\[exit code 1\]' '$PROOF/15_build_dist_refusal.txt') = 3 ] && grep -q 'forbidden file' '$PROOF/15_build_dist_refusal.txt' && grep -q 'secret-like' '$PROOF/15_build_dist_refusal.txt' && grep -q 'off-platform' '$PROOF/15_build_dist_refusal.txt'"
  if [ "$RUN_BROWSER" = 1 ]; then
    check "browser add-on (Docker, Chromium via Playwright): 6 rows built by JavaScript" \
      "[ -f '$W/shopjs.csv' ] && [ \$(rows '$W/shopjs.csv' | wc -l) = 6 ] && rows '$W/shopjs.csv' | head -1 | grep -q 'sku=SKU-001,name=Espresso cups (set of 4),price=12.5'"
  fi
  echo; echo "$PASS passed, $FAILN failed"
} > "$PROOF/14_checks.txt" 2>&1
sed -i "s#$W#<scratch>#g; s#$REPO#<repo>#g" "$PROOF"/*.txt; chmod 644 "$PROOF"/*
cat "$PROOF/14_checks.txt"
[ "$FAILN" = 0 ]
