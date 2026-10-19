#!/usr/bin/env bash
# Nyyo scraper kit - scrape public pages into CSV + JSON (+ your Google Sheet) on your own computer (Mac / Linux).
# Free 1-click install kit, MIT licence. Nyyo Automation.
#
#   ./setup.sh                    first run: creates config/scrape.toml, installs, scrapes the example site
#   ./setup.sh --check            check the config and robots.txt, scrape nothing
#   ./setup.sh --target books     only one target (repeatable) ;  --max-pages 1 for a quick test
#
# Options: --native (no Docker, Python venv), --browser (pages that need JavaScript), --no-open, --help
# Safe to run again: your config is never overwritten, installs are reused, outputs are replaced
# atomically (previous file kept as *.previous.csv), and an empty result never replaces a good one.
set -euo pipefail

KIT_VERSION="1.0.0"
KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$KIT_DIR/config/scrape.toml"
say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

NATIVE=0; BROWSER=0; OPEN=1; PASS=(); DOCKER_NET="${NYYO_DOCKER_NETWORK:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --native) NATIVE=1 ;;
    --browser) BROWSER=1 ;;
    --no-open) OPEN=0 ;;
    --check) PASS+=(--check) ;;
    --target|--max-pages) [ $# -ge 2 ] || die "$1 needs a value"; PASS+=("$1" "$2"); shift ;;
    -h|--help) usage ;;
    *) die "Unknown option: $1 (see ./setup.sh --help)" ;;
  esac; shift
done
[ -f "$KIT_DIR/scraper/nyyo_scrape.py" ] && [ -f "$KIT_DIR/requirements.txt" ] || die "Kit files missing: run this script from the unzipped kit folder."
cd "$KIT_DIR"
mkdir -p output credentials

# ---- 1. Your config (created once, never overwritten) ----
if [ ! -f "$CONFIG" ]; then
  cp config/scrape.example.toml "$CONFIG"
  say "Created config/scrape.toml from the example (scrapes the books.toscrape.com practice site)."
  say "Edit it later to set your own URLs and columns, then run ./setup.sh again."
fi
if [ "$BROWSER" = 0 ] && grep -Eq '^[[:space:]]*render[[:space:]]*=[[:space:]]*"browser"' "$CONFIG"; then
  warn 'A target uses render = "browser": add --browser so the browser add-on is installed.'
fi

# ---- 2. Engine: Docker (preferred) or a Python virtual environment ----
ENGINE=""
if [ "$NATIVE" = 0 ] && command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then ENGINE=docker
  else warn "Docker is installed but not running (open Docker Desktop to use it). Using Python instead."; fi
fi
if [ -z "$ENGINE" ]; then
  [ "$NATIVE" = 1 ] || command -v docker >/dev/null 2>&1 || warn "Docker not found. Using Python instead (no Docker needed)."
  ENGINE=native
fi

hash_files() { cat "$@" | { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } | cut -c1-16; }
REQ=requirements.txt; SUFFIX=""; MSG="about 1 minute"
if [ "$BROWSER" = 1 ]; then REQ=requirements-browser.txt; SUFFIX="-browser"; MSG="about 5 minutes, browser add-on included"; fi
DEPS_HASH="$(hash_files Dockerfile "$REQ")"

if [ "$ENGINE" = docker ]; then
  TAG="nyyo-scraper-kit:${KIT_VERSION}${SUFFIX}"
  HAVE="$(docker image inspect -f '{{index .Config.Labels "nyyo.deps"}}' "$TAG" 2>/dev/null || true)"
  if [ "$HAVE" = "$DEPS_HASH" ]; then say "Scraper image $TAG already installed."
  else
    say "Building the scraper image $TAG (first time only: ${MSG})..."
    docker build -q --build-arg BROWSER="$BROWSER" --label "nyyo.deps=$DEPS_HASH" -t "$TAG" . >/dev/null \
      || die "Docker could not build the image. Check your internet connection, then run ./setup.sh again."
    say "Image ready (Python 3.12, packages pinned by hash)."
  fi
  NET=(); if [ -n "$DOCKER_NET" ]; then NET=(--network "$DOCKER_NET"); fi
  set +e
  docker run --rm --init --user "$(id -u):$(id -g)" ${NET[@]+"${NET[@]}"} -e HOME=/tmp -e NYYO_IN_DOCKER=1 \
    -v "$KIT_DIR/scraper:/kit/scraper:ro" -v "$KIT_DIR/config:/kit/config:ro" \
    -v "$KIT_DIR/credentials:/kit/credentials:ro" -v "$KIT_DIR/output:/kit/output" \
    "$TAG" --config /kit/config/scrape.toml ${PASS[@]+"${PASS[@]}"}
  RC=$?; set -e
else
  PY=""
  for c in python3.13 python3.12 python3.11 python3.10 python3.9 python3; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null; then PY="$c"; break; fi
  done
  [ -n "$PY" ] || die "Python 3.9 or newer is needed (or install Docker Desktop). See INSTALL.md, Step 1."
  if [ "$BROWSER" = 1 ] && ! "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)'; then
    die "The browser add-on needs Python 3.10 or newer (you have $("$PY" -V)). Install a newer Python or use Docker."
  fi
  VENV="$KIT_DIR/.venv"; VPY="$VENV/bin/python"
  if [ ! -x "$VPY" ]; then
    say "Creating a private Python environment in .venv (uses $("$PY" -V))..."
    "$PY" -m venv "$VENV" || die "Could not create the environment. On Ubuntu/Debian: sudo apt install python3-venv"
  fi
  if [ "$(cat "$VENV/.nyyo-deps" 2>/dev/null)" = "$DEPS_HASH" ]; then say "Python packages already installed."
  else
    say "Installing pinned Python packages (checked by hash)..."
    "$VPY" -m pip install -q --disable-pip-version-check --require-hashes -r "$REQ" || die "Package install failed. Check your internet connection and run again."
    if [ "$BROWSER" = 1 ]; then say "Installing the Chromium browser for JavaScript pages..."; "$VPY" -m playwright install chromium; fi
    echo "$DEPS_HASH" > "$VENV/.nyyo-deps"
  fi
  set +e; "$VPY" scraper/nyyo_scrape.py --config "$CONFIG" ${PASS[@]+"${PASS[@]}"}; RC=$?; set -e
fi

echo
case "$RC" in
  0) say "Finished. Your files: $KIT_DIR/output" ;;
  1) warn "Finished with warnings (see [!] lines above). Your files: $KIT_DIR/output" ;;
  2) warn "No rows for at least one target: check the selectors in config/scrape.toml (INSTALL.md, Troubleshooting)." ;;
  3) die "Fix config/scrape.toml (see the message above) and run ./setup.sh again." ;;
  *) die "The scraper stopped with an error (code $RC). See INSTALL.md, Troubleshooting." ;;
esac
if [ "$OPEN" = 1 ] && [ -t 1 ] && [ "$RC" -lt 3 ]; then
  if [ "$(uname -s)" = Darwin ]; then open "$KIT_DIR/output"
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$KIT_DIR/output" >/dev/null 2>&1 || true; fi
fi
exit "$RC"
