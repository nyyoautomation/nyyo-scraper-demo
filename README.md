# Demo: Web scraper → clean CSV

**Nyyo Automation** portfolio sample.

## What it does
Scrapes [books.toscrape.com](https://books.toscrape.com/) (a public site made for scraping practice) and writes a deduplicated CSV with:

| column | meaning |
|--------|---------|
| title | book title |
| price_gbp | price as number |
| availability | stock text |
| rating | 1–5 stars |
| page | list page number |
| url | product URL |

## Run
```bash
pip install requests beautifulsoup4 lxml
python scrape_demo.py --pages 2 -o books_sample.csv
```

## Scope of a paid job
Same pattern for directories, catalogs, listings: you pick the columns, I deliver CSV/XLSX + the re-runnable script.  
**Not included:** sites behind login, personal/sensitive data, targets whose Terms forbid scraping.

## FREE · 1-click install kit included: run the scraper yourself
Included free with every package. A ready-made, polite scraper that runs on **your** computer: list the public pages and the columns you want in one settings file, run one command, get a clean **CSV** + **JSON** (and, if you want, a tab in your own Google Sheet). The first run scrapes the books.toscrape.com practice site so you can see it work before changing anything.

1. Download [`dist/nyyo-scraper-kit.zip`](https://github.com/nyyoautomation/nyyo-scraper-demo/raw/main/dist/nyyo-scraper-kit.zip) and unzip it.
2. Mac / Linux: `./setup.sh` · Windows: `powershell -ExecutionPolicy Bypass -File .\setup.ps1`
3. Open `output/books.csv`. Then put your own URLs and columns in `config/scrape.toml` and run it again.

- **Pinned:** Docker image (Python 3.12 by digest) or a Python venv, packages pinned by version and hash; optional Chromium (Playwright 1.64.0) for pages that need JavaScript.
- **Polite by default:** obeys robots.txt, waits between requests, backs off on "too many requests", user-agent `NyyoScraperKit/1.0.0`.
- **Safe to run again:** your settings are never overwritten, duplicates are removed, the previous file is kept, and an empty result never replaces a good one.

Beginner guide (Mac first) and troubleshooting: **[INSTALL.md](INSTALL.md)**. Test proof: [docs/TESTING.md](docs/TESTING.md) (23/23 checks: local test shop, books.toscrape.com, bash + PowerShell, Docker + Python). Licence: MIT ([LICENSE](LICENSE)).

| Path | Contents |
|---|---|
| `setup.sh`, `setup.ps1` | One-command install + run (Mac/Linux, Windows) |
| `scraper/nyyo_scrape.py` | The scraper (CSV, JSON, Google Sheets) |
| `config/scrape.example.toml` | Example settings: URLs, item selector, columns, polite limits |
| `Dockerfile`, `requirements*.txt` | Pinned runtime |
| `tests/`, `docs/kit-test-proof/` | Local test shop, from-scratch test and its raw output |
| `scripts/build_dist.sh` | Builds the ZIP; refuses to package keys, credentials or your own config |
| `dist/` | The kit ZIP and its SHA-256 |

Questions? Ask in your order chat.

## Price (typical)
- Up to ~1,000 rows / 1 site: **$69**
- Up to ~10,000 rows or 3 sites: **$139**  
Delivery: 2 days ($69) · 3 days ($139). Crypto only: USDC on BNB Chain or Base.

Contact: [LaborX — Nyyo Automation](https://laborx.com/freelancers/users/id475124) · [GitHub](https://github.com/nyyoautomation)
