#!/usr/bin/env python3
"""
Nyyo Automation — Public demo scraper
Scrapes books.toscrape.com (a site made for scraping practice).
Delivers a clean CSV: title, price, availability, rating, category, url.
No login, no personal data, no ToS-blocked targets.
"""
from __future__ import annotations

import argparse
import csv
import re
import sys
import time
from pathlib import Path
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

BASE = "https://books.toscrape.com/"
HEADERS = {
    "User-Agent": "NyyoAutomation-DemoScraper/1.0 (+https://github.com/nyyoautomation; demo portfolio)",
    "Accept": "text/html",
}
RATING_MAP = {"One": 1, "Two": 2, "Three": 3, "Four": 4, "Five": 5}


def fetch(url: str, session: requests.Session) -> BeautifulSoup:
    r = session.get(url, headers=HEADERS, timeout=30)
    r.raise_for_status()
    return BeautifulSoup(r.text, "lxml")


def parse_list_page(soup: BeautifulSoup, page_url: str) -> list[dict]:
    rows = []
    for article in soup.select("article.product_pod"):
        a = article.select_one("h3 a")
        title = a.get("title") or a.get_text(strip=True)
        href = a.get("href", "")
        url = urljoin(page_url, href)
        price_el = article.select_one("p.price_color")
        price = re.sub(r"[^0-9.]", "", price_el.get_text(strip=True)) if price_el else ""
        avail_el = article.select_one("p.instock.availability")
        availability = " ".join(avail_el.get_text().split()) if avail_el else ""
        rating_el = article.select_one("p.star-rating")
        rating = 0
        if rating_el:
            for cls in rating_el.get("class", []):
                if cls in RATING_MAP:
                    rating = RATING_MAP[cls]
                    break
        rows.append(
            {
                "title": title,
                "price_gbp": price,
                "availability": availability,
                "rating": rating,
                "url": url,
            }
        )
    return rows


def next_page(soup: BeautifulSoup, page_url: str) -> str | None:
    nxt = soup.select_one("li.next a")
    if not nxt:
        return None
    return urljoin(page_url, nxt["href"])


def scrape(max_pages: int, delay: float) -> list[dict]:
    session = requests.Session()
    url = BASE
    all_rows: list[dict] = []
    for page_num in range(1, max_pages + 1):
        soup = fetch(url, session)
        batch = parse_list_page(soup, url)
        for row in batch:
            row["page"] = page_num
        all_rows.extend(batch)
        print(f"page {page_num}: {len(batch)} books (total {len(all_rows)})", file=sys.stderr)
        nxt = next_page(soup, url)
        if not nxt:
            break
        url = nxt
        time.sleep(delay)
    # Deduplicate by URL
    seen = set()
    clean = []
    for row in all_rows:
        if row["url"] in seen:
            continue
        seen.add(row["url"])
        clean.append(row)
    return clean


def write_csv(rows: list[dict], path: Path) -> None:
    fields = ["title", "price_gbp", "availability", "rating", "page", "url"]
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def main() -> None:
    p = argparse.ArgumentParser(description="Demo scraper → clean CSV")
    p.add_argument("--pages", type=int, default=2, help="Max list pages (default 2 ≈ 40 books)")
    p.add_argument("--delay", type=float, default=0.5, help="Seconds between page requests")
    p.add_argument("-o", "--output", default="books_sample.csv", help="Output CSV path")
    args = p.parse_args()
    rows = scrape(args.pages, args.delay)
    out = Path(args.output)
    write_csv(rows, out)
    print(f"Wrote {len(rows)} rows → {out.resolve()}")


if __name__ == "__main__":
    main()
