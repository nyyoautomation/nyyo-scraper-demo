# Web scraper kit: one-command install (Mac, Windows, Linux)

This free kit runs a ready-made, **polite** web scraper on your own computer. You list the public pages and the
columns you want in one settings file; it gives you a clean **CSV** (opens in Excel, Numbers, Google Sheets) and a
**JSON** file, and can also fill a tab of **your own Google Sheet**. It is the free 1-click install kit that comes
with the web scraping gig. You don't need to know the command line: copy and paste the commands below.

- **Time needed:** about 5 minutes the first time (about 60 MB to download, 150 MB on disk). Then a few seconds per run.
- **Cost:** free. Open-source parts only (Python, requests, Beautiful Soup, lxml, gspread; Playwright for the
  optional browser add-on), each pinned to an exact version and checked by hash when installed.
- **Private:** everything runs on your computer. Nothing is sent to Nyyo Automation. Your Google key (optional)
  stays in the `credentials` folder and is only used to talk to Google.
- **Polite by default:** obeys each site's `robots.txt`, waits at least 0.5 s (1 s by default) between two requests
  to the same site, slows down and retries when a site says "too many requests", and identifies itself with a
  user-agent that names the tool (`NyyoScraperKit/1.0.0 (+https://github.com/nyyoautomation/nyyo-scraper-demo)`).
- **Safe to run again:** your settings are never overwritten, the install is reused, results are replaced in one
  step (the previous file is kept as `*.previous.csv`), duplicate rows are removed, and an empty result never
  replaces a good file.

> The very first run scrapes **books.toscrape.com**, a public practice site made for scraping, so you can check that
> everything works before you change anything. You get `output/books.csv` and `output/books.json`.

---

## Step 1. Install Docker Desktop (recommended) - or Python

The kit prefers Docker because it runs the scraper in a sealed box with exact versions. **No Docker? The kit still
works with Python 3.9 or newer** (3.10+ for the browser add-on): it creates a private environment in `.venv`.

### Mac
1. Go to https://www.docker.com/products/docker-desktop/ and download **Docker Desktop for Mac**.
   Pick **Apple chip** for M1/M2/M3/M4 Macs, **Intel chip** for older ones (Apple menu > About This Mac tells you which).
2. Open the downloaded `.dmg` and drag **Docker** into **Applications**.
3. Open **Docker** from Applications. Accept the terms. You can skip sign-in: no Docker account is needed.
4. Wait until Docker Desktop shows **Engine running**.

*No Docker on Mac:* install Python from https://www.python.org/downloads/macos/ (the "macOS 64-bit universal2
installer"), then use `./setup.sh --native` in Step 3.

### Windows 10/11
1. Download **Docker Desktop for Windows** from the same page and run the installer. Keep **Use WSL 2** ticked.
2. Restart Windows if asked. Open **Docker Desktop** and wait for **Engine running**. Sign-in is optional; skip it.

*No Docker on Windows:* install Python from https://www.python.org/downloads/windows/ and **tick "Add python.exe
to PATH"** on the first screen of the installer.

### Linux (Ubuntu / Debian)
Install Docker Engine following https://docs.docker.com/engine/install/ , then:
```bash
sudo usermod -aG docker "$USER"   # lets you run docker without sudo; log out and back in afterwards
```
Or without Docker: `sudo apt install python3 python3-venv`.

## Step 2. Unzip the kit and open a terminal in its folder

1. Unzip `nyyo-scraper-kit.zip`. You get a folder `nyyo-scraper-kit`.
2. Open a terminal in that folder:
   - **Mac:** open **Terminal** (Cmd + Space, type `Terminal`, Enter). Type `cd ` (with a space at the end),
     drag the `nyyo-scraper-kit` folder into the Terminal window, press **Enter**.
   - **Windows:** open the folder in File Explorer, click the address bar, type `powershell`, press **Enter**.
   - **Linux:** right-click inside the folder > **Open in Terminal**.

## Step 3. First run (example site)

### Mac / Linux
```bash
./setup.sh
```
### Windows
```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

The first run creates your settings file `config/scrape.toml`, installs the scraper, scrapes 3 pages of the practice
site and opens the `output` folder. You should see `-> 60 rows (0 duplicate(s) removed) from 3 page(s)`.

## Step 4. Scrape your own pages

Open `config/scrape.toml` with any text editor (Mac: TextEdit; Windows: Notepad) and edit the `[[target]]` block:

| Setting | What to put |
|---|---|
| `name` | A short name: it becomes the file name (`output/<name>.csv`) and the Google Sheets tab |
| `start_urls` | The page(s) where the list starts, between quotes: `["https://example.com/catalog"]` |
| `items` | The CSS selector of **one item** of the list (one row of your file), for example `"div.product"` |
| `next_page` | The CSS selector of the "next page" link, or `""` if there is only one page |
| `max_pages` | Safety cap: the kit stops after this many pages |
| `unique_by` | The column(s) that identify a row, for example `["url"]`, to remove duplicates |
| `[target.fields]` | One line per column: `price = { css = "span.price", type = "number" }` |

Each column can use: `css` (selector inside the item; leave it out to read the item itself), `attr` (an attribute
such as `"href"`, `"title"`, `"data-id"`; leave it out to get the visible text), `type` (`"text"`, `"number"`,
`"int"`, or `"url"` to turn a relative link into a full one), `regex` (keep only the part that matches; the first
`( )` group if there is one), `map` (replace words, for example star ratings), and `all = true` (join every match
with ` | ` instead of keeping the first).

**How to find a selector:** in Chrome, right-click the element on the page > **Inspect**. In the panel, right-click
the highlighted line > **Copy > Copy selector**, then shorten it to the class names (`div.product`, `span.price`).

Need more sites? Copy the whole `[[target]]` block (with its `[target.fields]`) under the first one and give it
another `name`. Then check before scraping:
```bash
./setup.sh --check          # Windows: powershell -ExecutionPolicy Bypass -File .\setup.ps1 -Check
./setup.sh --max-pages 1    # quick test on one page; Windows: ... .\setup.ps1 -MaxPages 1
./setup.sh                  # full run
```
`--check` validates your file and tells you, for each start URL, whether the site's `robots.txt` allows it.

### Options
| Mac / Linux | Windows | What it does |
|---|---|---|
| `--check` | `-Check` | Check the settings and robots.txt, scrape nothing |
| `--target NAME` | `-Target NAME` | Run only one target (repeatable) |
| `--max-pages N` | `-MaxPages N` | Override the page cap for this run (use 1 for a quick test) |
| `--native` | `-Native` | Don't use Docker, use Python in a private `.venv` |
| `--browser` | `-Browser` | Install the browser add-on (Chromium via Playwright) for `render = "browser"` targets |
| `--no-open` | `-NoOpen` | Don't open the output folder at the end |

**Pages that need JavaScript:** if a page shows its list only after it loads (your selectors work in Chrome but the
kit finds 0 items), set `render = "browser"` in that target and run `./setup.sh --browser`. The first browser
install takes a few minutes and about 1.4 GB of disk space with Docker (Chromium and its system libraries).

## Step 5 (optional). Send the results to your Google Sheet

1. Follow `credentials/README.md` to create **your own** Google service-account key (free, about 5 minutes) and put it
   in `credentials/service-account.json`.
2. Share your sheet with the `client_email` of that key as **Editor**.
3. In `config/scrape.toml`, under `[google_sheets]`: `enabled = true` and paste the sheet id into `spreadsheet_id`.

Each target fills its own tab, replaced (never appended) on every run. If Google refuses, your CSV and JSON are still
written and the terminal tells you what to fix.

## What you get
- `output/<name>.csv`: UTF-8 (accents display correctly in Excel), one row per item, your columns plus
  `source_url`, `page` and `scraped_at` (date and time of the run, with its time zone).
- `output/<name>.json`: the same rows, for developers and other tools.
- `output/<name>.previous.csv` / `.previous.json`: the result of the run before, so you can compare.

**Exit codes** (for scripts and schedulers): 0 = OK, 1 = done with warnings, 2 = a target returned no rows,
3 = settings problem.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Mac: `permission denied: ./setup.sh` | Run `chmod +x setup.sh` once, or start it with `bash setup.sh`. |
| `Docker is installed but not running` | Open Docker Desktop and wait for **Engine running**, then run again. Or ignore it: the kit falls back to Python. |
| Docker: `permission denied ... docker.sock` (Linux) | Run `sudo usermod -aG docker "$USER"`, log out and back in. |
| `Python 3.9 or newer is needed` | Install Docker Desktop (Step 1), or Python from python.org. Mac: the old system Python is not enough. |
| Linux: `Could not create the environment` | `sudo apt install python3-venv`, then run again. |
| Windows: "running scripts is disabled on this system" | Use the exact command above (`powershell -ExecutionPolicy Bypass -File .\setup.ps1`). It changes nothing permanently. |
| Windows: `python` opens the Microsoft Store | Install Python from python.org with "Add python.exe to PATH" ticked, or use Docker. |
| Windows: Docker "Mounts denied" | Docker Desktop > Settings > Resources > File sharing: add the drive of the kit folder. Or use `-Native`. |
| `Config problem: ... is not valid TOML` | A quote or bracket is missing on the line shown. Text values need `"double quotes"`. |
| `0 rows. Check 'items'` | The `items` selector matches nothing. Re-check it with Inspect. If it works in Chrome, the page probably needs JavaScript: use `render = "browser"` and `--browser`. |
| `0 rows this time, so your previous file was kept` | The site was down or changed its layout. Your last good file is untouched. Update the selectors. |
| A column is empty | Its `css` selector (inside the item) or its `attr` is wrong. Try without `attr` to see the text. |
| `robots.txt ... does not allow` | The site owner asked robots not to visit that page. The kit respects it. Use the site's official export or API instead, or ask the owner. |
| `HTTP 429` / `waiting ... then retrying` | The site asks to slow down. The kit waits and retries by itself. If it happens a lot, raise `delay_seconds`. |
| `HTTP 403` | The site blocks automated visits. Don't try to get around it: check its terms or ask for access. |
| `Google refused access` / `sheet not found` | Share the sheet with the `client_email` of your key as **Editor**, and check `spreadsheet_id`. |
| `With Docker, keep [output] folder = "output"` | With Docker only the `output` folder is shared with your computer. Use `--native` if you need another folder. |

## Scrape responsibly
Use the kit on **public** pages you are allowed to collect: product lists, directories, listings, your own sites.
Not on pages behind a login, not for personal data you have no right to process, and not where a site's terms forbid
it. The polite defaults (robots.txt, delays, a clear user-agent) are on for that reason. Only set
`obey_robots_txt = false` for a site you own or have written permission for.

## Honest limits
- Works with pages whose list is in the HTML, or rendered by JavaScript with the browser add-on. It does not log in,
  solve CAPTCHAs or follow each item to its own detail page.
- When a site changes its layout, the selectors must be updated.
- Tested on Linux (Docker and Python, bash and PowerShell 7), against a local test shop and books.toscrape.com.
  Not yet tested on a real Mac or a Windows PC, nor with Windows PowerShell 5.1. The Google Sheets export was tested
  with a stand-in for Google's library, not against a real Google account. See
  [docs/TESTING.md](https://github.com/nyyoautomation/nyyo-scraper-demo/blob/main/docs/TESTING.md).

Questions? Ask in your order chat.

Nyyo Automation · Remote · Worldwide
