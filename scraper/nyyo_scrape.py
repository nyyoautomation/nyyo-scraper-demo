#!/usr/bin/env python3
"""Nyyo scraper kit: scrape public pages into clean CSV + JSON (and optionally your Google Sheet).

Usage (setup.sh / setup.ps1 call this for you):
    python scraper/nyyo_scrape.py --config config/scrape.toml [--target NAME] [--max-pages N] [--check]

Polite by default: obeys robots.txt (RFC 9309), waits between requests to the same site,
retries 429/5xx with back-off, and sends a user-agent that names the tool.
Safe to run again: outputs are replaced atomically, the previous result is kept as *.previous.*,
rows are de-duplicated, and an empty result never overwrites a good one.
MIT licence. Nyyo Automation.
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import os
import re
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib import robotparser
from urllib.parse import urljoin, urlsplit

try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib  # type: ignore

import requests
from bs4 import BeautifulSoup

VERSION = "1.0.0"
TOOL_URL = "https://github.com/nyyoautomation/nyyo-scraper-demo"
MIN_DELAY = 0.5
MAX_RETRY_WAIT = 60.0
KIT_DIR = Path(__file__).resolve().parent.parent
FIELD_TYPES = {"text", "number", "int", "url"}
RESERVED = {"source_url", "page", "scraped_at"}


class ConfigError(Exception):
    pass


def log(msg: str) -> None:
    print(msg, flush=True)


def warn(msg: str) -> None:
    print(f"[!] {msg}", file=sys.stderr, flush=True)


# ---------------------------------------------------------------- config
def load_config(path: Path) -> dict:
    if not path.is_file():
        raise ConfigError(f"Config file not found: {path}")
    try:
        with path.open("rb") as fh:
            cfg = tomllib.load(fh)
    except tomllib.TOMLDecodeError as exc:
        raise ConfigError(f"{path.name} is not valid TOML: {exc}. Tip: text values need \"double quotes\".") from exc

    out = cfg.setdefault("output", {})
    out.setdefault("folder", "output")
    out.setdefault("formats", ["csv", "json"])
    bad = set(out["formats"]) - {"csv", "json"}
    if bad:
        raise ConfigError(f"[output] formats: unknown {sorted(bad)} (use \"csv\" and/or \"json\")")

    pol = cfg.setdefault("polite", {})
    pol.setdefault("obey_robots_txt", True)
    pol.setdefault("delay_seconds", 1.0)
    pol.setdefault("max_pages", 5)
    pol.setdefault("timeout_seconds", 30)
    pol.setdefault("retries", 3)
    pol.setdefault("contact_url", "")
    if float(pol["delay_seconds"]) < MIN_DELAY:
        warn(f"delay_seconds={pol['delay_seconds']} is too fast; using the minimum {MIN_DELAY}s.")
        pol["delay_seconds"] = MIN_DELAY
    if pol["contact_url"] and "@" in str(pol["contact_url"]):
        raise ConfigError("[polite] contact_url must be a web address (https://...), not an e-mail address.")

    gs = cfg.setdefault("google_sheets", {})
    gs.setdefault("enabled", False)
    gs.setdefault("credentials_file", "credentials/service-account.json")
    gs.setdefault("spreadsheet_id", "")

    targets = cfg.get("target")
    if not targets:
        raise ConfigError("No [[target]] block in the config: add at least one site to scrape.")
    names = set()
    for i, t in enumerate(targets, 1):
        where = f"[[target]] #{i}"
        for key in ("name", "start_urls", "items", "fields"):
            if key not in t:
                raise ConfigError(f"{where}: missing '{key}'.")
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,40}", t["name"]):
            raise ConfigError(f"{where}: name '{t['name']}' must be letters, digits, - or _ (it becomes the file name).")
        if t["name"] in names:
            raise ConfigError(f"{where}: name '{t['name']}' is used twice.")
        names.add(t["name"])
        if isinstance(t["start_urls"], str):
            t["start_urls"] = [t["start_urls"]]
        for u in t["start_urls"]:
            if urlsplit(u).scheme not in ("http", "https"):
                raise ConfigError(f"{where}: start URL must start with http:// or https:// ({u})")
        t.setdefault("next_page", "")
        t.setdefault("render", "html")
        t.setdefault("wait_for", t["items"])
        t.setdefault("max_pages", pol["max_pages"])
        if t["render"] not in ("html", "browser"):
            raise ConfigError(f"{where}: render must be \"html\" or \"browser\".")
        if not isinstance(t["fields"], dict) or not t["fields"]:
            raise ConfigError(f"{where}: [target.fields] must list at least one column.")
        for fname, spec in t["fields"].items():
            if fname in RESERVED:
                raise ConfigError(f"{where}: column name '{fname}' is reserved (the kit adds it).")
            if isinstance(spec, str):
                spec = t["fields"][fname] = {"css": spec}
            spec.setdefault("css", "")
            spec.setdefault("attr", "")
            spec.setdefault("type", "text")
            if spec["type"] not in FIELD_TYPES:
                raise ConfigError(f"{where}: field '{fname}' type must be one of {sorted(FIELD_TYPES)}.")
            if spec.get("regex"):
                try:
                    re.compile(spec["regex"])
                except re.error as exc:
                    raise ConfigError(f"{where}: field '{fname}' regex is invalid: {exc}") from exc
        t.setdefault("unique_by", [])
        for k in t["unique_by"]:
            if k not in t["fields"] and k not in ("source_url",):
                raise ConfigError(f"{where}: unique_by '{k}' is not one of the fields.")
    return cfg


def user_agent(cfg: dict) -> str:
    ua = f"NyyoScraperKit/{VERSION} (+{TOOL_URL})"
    if cfg["polite"]["contact_url"]:
        ua += f" operator: {cfg['polite']['contact_url']}"
    return ua


# ---------------------------------------------------------------- polite fetching
class Fetcher:
    def __init__(self, cfg: dict):
        pol = cfg["polite"]
        self.ua = user_agent(cfg)
        self.delay = float(pol["delay_seconds"])
        self.timeout = float(pol["timeout_seconds"])
        self.retries = int(pol["retries"])
        self.obey = bool(pol["obey_robots_txt"])
        self.session = requests.Session()
        self.session.headers.update({"User-Agent": self.ua, "Accept": "text/html,application/xhtml+xml"})
        self.robots: dict[str, robotparser.RobotFileParser | str] = {}
        self.last_hit: dict[str, float] = {}
        self.browser = None
        self.requests_made = 0

    def _wait_turn(self, origin: str, extra: float = 0.0) -> None:
        gap = max(self.delay, extra)
        last = self.last_hit.get(origin)
        if last is not None:
            sleep = last + gap - time.monotonic()
            if sleep > 0:
                time.sleep(sleep)
        self.last_hit[origin] = time.monotonic()

    def _robots(self, origin: str):
        if origin in self.robots:
            return self.robots[origin]
        url = origin + "/robots.txt"
        rp = robotparser.RobotFileParser(url)
        try:
            self._wait_turn(origin)
            r = self.session.get(url, timeout=self.timeout)
            self.requests_made += 1
            if r.status_code in (401, 403):
                res = "deny"  # RFC 9309: access restricted -> treat as fully disallowed
            elif 400 <= r.status_code < 500:
                res = "allow"  # no robots.txt -> no restriction
            elif r.status_code >= 500:
                res = "deny"  # unreachable -> assume complete disallow
            else:
                rp.parse(r.text.splitlines())
                res = rp
        except requests.RequestException as exc:
            warn(f"Could not read {url} ({exc.__class__.__name__}); not scraping this site to stay polite.")
            res = "deny"
        self.robots[origin] = res
        return res

    def allowed(self, url: str) -> tuple[bool, float]:
        if not self.obey:
            return True, 0.0
        p = urlsplit(url)
        rp = self._robots(f"{p.scheme}://{p.netloc}")
        if rp == "allow":
            return True, 0.0
        if rp == "deny":
            return False, 0.0
        agent = "NyyoScraperKit"
        crawl = rp.crawl_delay(agent) or 0.0
        return rp.can_fetch(agent, url), float(crawl)

    def get(self, url: str, render: str, wait_for: str) -> str:
        p = urlsplit(url)
        origin = f"{p.scheme}://{p.netloc}"
        _, crawl = self.allowed(url)
        attempt = 0
        while True:
            self._wait_turn(origin, crawl)
            attempt += 1
            try:
                if render == "browser":
                    return self._browser_get(url, wait_for)
                r = self.session.get(url, timeout=self.timeout)
                self.requests_made += 1
                if r.status_code == 429 or r.status_code >= 500:
                    raise _Retry(r.status_code, r.headers.get("Retry-After"))
                r.raise_for_status()
                r.encoding = r.encoding if r.encoding and r.encoding.lower() != "iso-8859-1" else r.apparent_encoding
                return r.text
            except (_Retry, requests.ConnectionError, requests.Timeout) as exc:
                if attempt > self.retries:
                    raise RuntimeError(f"{url}: gave up after {attempt} tries ({exc})") from None
                wait = min(MAX_RETRY_WAIT, 2.0 ** attempt)
                if isinstance(exc, _Retry) and exc.retry_after:
                    try:
                        wait = min(MAX_RETRY_WAIT, max(wait, float(exc.retry_after)))
                    except ValueError:
                        pass
                warn(f"{url}: {exc}; waiting {wait:.0f}s then retrying ({attempt}/{self.retries}).")
                time.sleep(wait)

    def _browser_get(self, url: str, wait_for: str) -> str:
        if self.browser is None:
            try:
                from playwright.sync_api import sync_playwright
            except ModuleNotFoundError:
                raise RuntimeError('render = "browser" needs the browser add-on: run ./setup.sh --browser '
                                   "(Windows: .\\setup.ps1 -Browser).") from None
            self._pw = sync_playwright().start()
            self.browser = self._pw.chromium.launch()
            self._ctx = self.browser.new_context(user_agent=self.ua)
        page = self._ctx.new_page()
        try:
            resp = page.goto(url, timeout=self.timeout * 1000, wait_until="domcontentloaded")
            self.requests_made += 1
            if resp is not None and (resp.status == 429 or resp.status >= 500):
                raise _Retry(resp.status, resp.headers.get("retry-after"))
            if resp is not None and resp.status >= 400:
                raise RuntimeError(f"{url}: HTTP {resp.status}")
            try:
                page.wait_for_selector(wait_for, timeout=self.timeout * 1000)
            except Exception:
                warn(f"{url}: '{wait_for}' did not appear within {self.timeout:.0f}s.")
            return page.content()
        finally:
            page.close()

    def close(self) -> None:
        if self.browser is not None:
            self.browser.close()
            self._pw.stop()


class _Retry(Exception):
    def __init__(self, status: int, retry_after: str | None):
        super().__init__(f"HTTP {status}")
        self.retry_after = retry_after


# ---------------------------------------------------------------- parsing
NUM_RE = re.compile(r"-?\d[\d,.\s\u00a0\u202f']*")


def to_number(s: str) -> float | int | str:
    m = NUM_RE.search(s)
    if not m:
        return ""
    raw = re.sub(r"[\s\u00a0\u202f']", "", m.group(0)).rstrip(".,")
    if "," in raw and "." in raw:
        raw = raw.replace(",", "") if raw.rfind(".") > raw.rfind(",") else raw.replace(".", "").replace(",", ".")
    elif "," in raw:
        head, _, tail = raw.rpartition(",")
        raw = raw.replace(",", "") if len(tail) == 3 and head else raw.replace(",", ".")
    try:
        val = float(raw)
    except ValueError:
        return ""
    return int(val) if val.is_integer() else val


def extract(item, spec: dict, page_url: str):
    els = item.select(spec["css"]) if spec["css"] else [item]
    if not spec.get("all"):
        els = els[:1]
    values = []
    for el in els:
        attr = spec["attr"]
        if attr == "class":
            v = " ".join(el.get("class", []))
        elif attr:
            v = el.get(attr, "") or ""
        else:
            v = " ".join(el.get_text(" ").split())
        if spec.get("regex"):
            m = re.search(spec["regex"], v)
            v = (m.group(1) if m and m.groups() else m.group(0)) if m else ""
        if spec.get("map"):
            v = next((str(out) for key, out in spec["map"].items() if key in v.split() or key == v), v)
        t = spec["type"]
        if t == "url" and v:
            v = urljoin(page_url, v)
        elif t == "number":
            v = to_number(v)
        elif t == "int":
            n = to_number(v)
            v = int(n) if isinstance(n, (int, float)) else ""
        values.append(v)
    if spec.get("all"):
        return " | ".join(str(v) for v in values if v != "")
    return values[0] if values else ""


def scrape_target(t: dict, fetcher: Fetcher, max_pages_cli: int | None) -> tuple[list[dict], dict]:
    max_pages = int(max_pages_cli or t["max_pages"])
    stats = {"pages": 0, "blocked": [], "errors": [], "raw_rows": 0}
    rows: list[dict] = []
    stamp = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")
    for start in t["start_urls"]:
        url, page_no, seen_pages = start, 0, set()
        while url and page_no < max_pages and url not in seen_pages:
            ok, _ = fetcher.allowed(url)
            if not ok:
                warn(f"robots.txt of {urlsplit(url).netloc} does not allow {url}: skipped.")
                stats["blocked"].append(url)
                break
            seen_pages.add(url)
            try:
                html = fetcher.get(url, t["render"], t["wait_for"])
            except Exception as exc:  # keep what we have, report the rest
                warn(str(exc))
                stats["errors"].append(f"{url}: {exc}")
                break
            page_no += 1
            stats["pages"] += 1
            soup = BeautifulSoup(html, "lxml")
            items = soup.select(t["items"])
            for it in items:
                row = {name: extract(it, spec, url) for name, spec in t["fields"].items()}
                row.update(source_url=url, page=page_no, scraped_at=stamp)
                rows.append(row)
            log(f"  {t['name']}: page {page_no} -> {len(items)} item(s)  {url}")
            nxt = soup.select_one(t["next_page"]) if t["next_page"] else None
            url = urljoin(url, nxt.get("href", "")) if nxt is not None and nxt.get("href") else ""
            if url and urlsplit(url).netloc != urlsplit(start).netloc:
                warn(f"next page {url} is on another site: stopped there.")
                url = ""
    stats["raw_rows"] = len(rows)
    keys = t["unique_by"] or list(t["fields"])
    seen, clean = set(), []
    for r in rows:
        k = tuple(str(r.get(c, "")) for c in keys)
        if k in seen:
            continue
        seen.add(k)
        clean.append(r)
    return clean, stats


# ---------------------------------------------------------------- outputs
def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        if path.exists():
            prev = path.with_name(f"{path.stem}.previous{path.suffix}")
            os.replace(path, prev)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def write_outputs(name: str, rows: list[dict], columns: list[str], folder: Path, formats: list[str]) -> list[Path]:
    written = []
    if "csv" in formats:
        buf = io.StringIO()
        w = csv.DictWriter(buf, fieldnames=columns, lineterminator="\r\n", extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
        p = folder / f"{name}.csv"
        atomic_write(p, ("\ufeff" + buf.getvalue()).encode("utf-8"))  # BOM so Excel opens accents correctly
        written.append(p)
    if "json" in formats:
        p = folder / f"{name}.json"
        atomic_write(p, (json.dumps(rows, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
        written.append(p)
    return written


def push_sheets(cfg: dict, name: str, rows: list[dict], columns: list[str]) -> str:
    gs = cfg["google_sheets"]
    cred = Path(gs["credentials_file"])
    cred = cred if cred.is_absolute() else KIT_DIR / cred
    if not gs["spreadsheet_id"]:
        raise RuntimeError("[google_sheets] spreadsheet_id is empty (copy it from the sheet URL, between /d/ and /edit).")
    if not cred.is_file():
        raise RuntimeError(f"credentials file not found: {cred} (see credentials/README.md).")
    try:
        email = json.loads(cred.read_text(encoding="utf-8")).get("client_email", "?")
    except (ValueError, OSError):
        raise RuntimeError(f"{cred.name} is not a Google service-account JSON key.") from None
    import gspread

    gc = gspread.service_account(filename=str(cred))
    try:
        sh = gc.open_by_key(gs["spreadsheet_id"])
    except gspread.exceptions.APIError as exc:
        raise RuntimeError(f"Google refused access ({exc}). Share the sheet with {email} as Editor.") from None
    except gspread.exceptions.SpreadsheetNotFound:
        raise RuntimeError(f"sheet not found or not shared with {email}: share it as Editor.") from None
    try:
        ws = sh.worksheet(name)
    except gspread.exceptions.WorksheetNotFound:
        ws = sh.add_worksheet(title=name, rows=max(len(rows) + 1, 10), cols=max(len(columns), 1))
    values = [columns] + [["" if r.get(c) is None else r.get(c) for c in columns] for r in rows]
    ws.clear()  # replace, never append: running again does not duplicate rows
    ws.update(values=values, range_name="A1")
    return f"tab '{name}' ({len(rows)} rows)"


# ---------------------------------------------------------------- main
def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Nyyo scraper kit: public pages -> CSV + JSON (+ Google Sheets).")
    ap.add_argument("--config", default=str(KIT_DIR / "config" / "scrape.toml"))
    ap.add_argument("--target", action="append", help="only this target (repeatable)")
    ap.add_argument("--max-pages", type=int, help="override max_pages for this run (e.g. 1 for a quick test)")
    ap.add_argument("--check", action="store_true", help="check the config and robots.txt, scrape nothing")
    ap.add_argument("--version", action="version", version=f"nyyo-scraper-kit {VERSION}")
    a = ap.parse_args(argv)

    try:
        cfg = load_config(Path(a.config))
    except ConfigError as exc:
        warn(f"Config problem: {exc}")
        return 3
    targets = cfg["target"]
    if a.target:
        unknown = set(a.target) - {t["name"] for t in targets}
        if unknown:
            warn(f"Unknown target(s): {', '.join(sorted(unknown))}")
            return 3
        targets = [t for t in targets if t["name"] in a.target]

    fetcher = Fetcher(cfg)
    log(f"Nyyo scraper kit {VERSION} | user-agent: {fetcher.ua}")
    log(f"Polite mode: robots.txt {'obeyed' if fetcher.obey else 'IGNORED (you turned it off)'}, "
        f"{fetcher.delay:g}s between requests per site, max {cfg['polite']['max_pages']} pages per target.")
    if not fetcher.obey:
        warn("obey_robots_txt = false: only do this on a site you own or have permission to scrape.")

    if a.check:
        for t in targets:
            for u in t["start_urls"]:
                ok, crawl = fetcher.allowed(u)
                extra = f" (crawl-delay {crawl:g}s)" if crawl else ""
                log(f"  {t['name']}: {u} -> {'allowed' if ok else 'BLOCKED by robots.txt'}{extra}")
        log("Config OK.")
        return 0

    folder = Path(cfg["output"]["folder"])
    folder = folder if folder.is_absolute() else KIT_DIR / folder
    if os.environ.get("NYYO_IN_DOCKER") == "1" and folder.resolve() != (KIT_DIR / "output").resolve():
        warn('With Docker, keep [output] folder = "output" (only that folder is shared with your computer).')
        return 3
    status = 0
    try:
        for t in targets:
            log(f"Scraping '{t['name']}'...")
            rows, st = scrape_target(t, fetcher, a.max_pages)
            columns = list(t["fields"]) + ["source_url", "page", "scraped_at"]
            prev = folder / f"{t['name']}.csv"
            if not rows and st["blocked"] and not st["pages"]:
                status = max(status, 1)
                warn(f"'{t['name']}': nothing scraped, robots.txt forbids it (this is the site owner's choice).")
                continue
            if not rows:
                status = max(status, 2)
                if prev.exists():
                    warn(f"'{t['name']}': 0 rows this time, so your previous file {prev.name} was kept unchanged "
                         "(the site may be down or its layout changed: check the selectors).")
                else:
                    warn(f"'{t['name']}': 0 rows. Check 'items' and the field selectors in the config.")
                continue
            files = write_outputs(t["name"], rows, columns, folder, cfg["output"]["formats"])
            dup = st["raw_rows"] - len(rows)
            log(f"  -> {len(rows)} rows ({dup} duplicate(s) removed) from {st['pages']} page(s): "
                + ", ".join(str(p.relative_to(KIT_DIR)) if p.is_relative_to(KIT_DIR) else str(p) for p in files))
            if st["errors"] or st["blocked"]:
                status = max(status, 1)
            if cfg["google_sheets"]["enabled"]:
                try:
                    log(f"  -> Google Sheets: {push_sheets(cfg, t['name'], rows, columns)}")
                except Exception as exc:
                    warn(f"Google Sheets skipped: {exc} Your CSV/JSON files are fine.")
                    status = max(status, 1)
    finally:
        fetcher.close()
    shown = "output/" if os.environ.get("NYYO_IN_DOCKER") == "1" else str(folder)
    log(f"Done. {fetcher.requests_made} request(s) sent. Files are in {shown}")
    return status


if __name__ == "__main__":
    sys.exit(main())
