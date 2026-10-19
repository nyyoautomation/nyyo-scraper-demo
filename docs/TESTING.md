# Scraper kit: test report

Tested on **Oct 19, 2026** on the build box: Linux x86_64, Docker Engine 26.1, Python 3.13 on the host,
PowerShell 7 (Linux). Raw output of every step: [`kit-test-proof/`](kit-test-proof/). The test is scripted:
`tests/run_kit_test.sh` (repo only), and the result is in [14_checks.txt](kit-test-proof/14_checks.txt).

## From scratch
1. The kit images were **deleted** first and the shipped ZIP was unzipped into an **empty folder** (no config, no
   `.venv`, no `output`).
2. **Buyer's first run**, no settings changed: `./setup.sh` created `config/scrape.toml` from the example, built the
   image and scraped 3 pages of **books.toscrape.com** (a public practice site). Then once more.
3. The config was replaced by a **local fixture shop** served on the box (`tests/fixture_server.py`): 3 pages,
   25 items with one duplicate, prices written in different ways (`$1,299.00`, `USD 45`), missing ratings, relative
   links, a `robots.txt` that forbids `/private/`, and a page 2 that answers **429 Too Many Requests** the first time.
   It logs every request (time, path, status, user-agent).
4. The same scrape was repeated: `setup.sh` (Docker, twice), `setup.sh --native` (new venv, then reuse),
   `setup.ps1` under PowerShell 7 with Docker, then `-Native` (new venv, then reuse).
5. Safety and options: a broken selector, Google Sheets without a key, Google Sheets through a stand-in for Google's
   library, and the browser add-on on a page that builds its list with JavaScript.

## Results (23 of 23 checks passed)
| Check | Result |
|---|---|
| books.toscrape.com, first run | **60 rows** from 3 pages, every row has title, price, availability, rating 1-5 and a full URL; JSON = CSV |
| Fixture shop | **24 rows exactly as expected** (25 items, 1 duplicate removed); `$1,299.00` -> 1299, `USD 45` -> 45, empty rating left empty |
| robots.txt | Read first; `/private/` **never requested**; the target is reported as blocked by the site owner |
| Rate limit | At least **0.5 s** between any two requests to the site (server log) |
| HTTP 429 | Waited, retried, page 2 scraped |
| User-agent | `NyyoScraperKit/1.0.0 (+https://github.com/nyyoautomation/nyyo-scraper-demo)` on every request |
| Running again | Image / venv reused, config not overwritten, same rows, no duplicates, previous file kept as `*.previous.csv` |
| Bash vs PowerShell, Docker vs native Python | Identical rows |
| Broken selector | Exit code 2, **previous good file kept byte for byte** |
| Google Sheets, no key | Clear message, CSV/JSON still written, exit code 1 |
| Google Sheets, stand-in library | Tab created, cleared, then filled with header + 24 rows at A1 (replace, never append) |
| Browser add-on (Docker) | 6 rows rendered by JavaScript, read with Chromium via Playwright 1.64.0 |
| `scripts/build_dist.sh` | Builds the ZIP; **refuses** a Google key file in `credentials/`, a fake key pasted into `INSTALL.md` and off-platform contact details (see [15_build_dist_refusal.txt](kit-test-proof/15_build_dist_refusal.txt)) |

Samples: [books CSV](kit-test-proof/sample-books.csv), [fixture CSV](kit-test-proof/sample-shop.csv),
[fixture JSON](kit-test-proof/sample-shop.json), [server log](kit-test-proof/03b_server_log_fixture.txt).

## Not tested
- Docker Desktop on a real Mac or Windows PC, Python on macOS / Windows, and Windows PowerShell 5.1 (the script
  avoids PowerShell 7-only syntax).
- A real Google account: the Sheets export was checked with a stand-in that records the calls the kit makes.
- The browser add-on without Docker. The Docker build cache on the box was warm, so the timings in the logs are
  faster than a real first install.
