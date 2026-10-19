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

## Price (typical)
- Up to ~1,000 rows / 1 site: **$69**
- Up to ~10,000 rows or 3 sites: **$139**  
Delivery: 2 days ($69) · 3 days ($139). Crypto only: USDC on BNB Chain or Base.

Contact: [LaborX — Nyyo Automation](https://laborx.com/freelancers/users/id475124) · [GitHub](https://github.com/nyyoautomation)
