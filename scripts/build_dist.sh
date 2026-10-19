#!/usr/bin/env bash
# Build dist/nyyo-scraper-kit.zip from the repo. Refuses to package anything that looks like a secret,
# a buyer's own config/credentials/output, or off-platform contact or payment wording.
#   scripts/build_dist.sh
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO"
GL_IMAGE="zricethezav/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"
OUT="$REPO/dist/nyyo-scraper-kit.zip"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
D="$STAGE/nyyo-scraper-kit"; mkdir -p "$D"

FILES="setup.sh setup.ps1 INSTALL.md LICENSE Dockerfile .dockerignore requirements.in requirements.txt
requirements-browser.in requirements-browser.txt scraper/nyyo_scrape.py config/scrape.example.toml
credentials/README.md tests/fixture_server.py tests/fixture.toml tests/fixture-browser.toml"
for f in $FILES; do mkdir -p "$D/$(dirname "$f")"; cp "$f" "$D/$f"; done
# anything extra a developer dropped into the shipped folders gets copied too, so the checks below see it
for dir in credentials config scraper; do
  find "$dir" -type f ! -name '*.pyc' ! -path '*/__pycache__/*' -print0 | while IFS= read -r -d '' f; do
    [ -e "$D/$f" ] || { mkdir -p "$D/$(dirname "$f")"; cp "$f" "$D/$f"; }; done
done
sed -i 's/\r$//; s/$/\r/' "$D/setup.ps1"          # Windows line endings for the PowerShell script
chmod 755 "$D/setup.sh"

# 1. Forbidden files (secrets, the buyer's own config, outputs, environments)
BAD="$(cd "$D" && find . \( -name '.env' -o -name '.env.*' -o -name '*.pem' -o -name '*.key' -o -name '*.p12' -o -name '*.pfx' \
  -o -name 'id_rsa*' -o -name 'id_ed25519*' -o -name '*.kdbx' -o -path './output/*' -o -path './.venv/*' \
  -o -path './config/scrape.toml' -o \( -path './credentials/*' ! -name README.md \) \) -print)"
[ -z "$BAD" ] || { echo "refusing: forbidden file(s) in kit:"; echo "$BAD"; exit 1; }

# 2. gitleaks on the staged kit (pinned image)
docker info >/dev/null 2>&1 || { echo "refusing: Docker is needed to run the gitleaks check"; exit 1; }
rc=0; docker run --rm --user "$(id -u):$(id -g)" -v "$D:/scan:ro" "$GL_IMAGE" dir /scan --no-banner --redact -v --exit-code 3 -l warn || rc=$?
[ "$rc" = 3 ] && { echo "refusing: gitleaks found secret-like strings in the kit (values redacted above)"; exit 1; }
[ "$rc" = 0 ] || { echo "refusing: the gitleaks check failed to run (exit $rc)"; exit 1; }
echo "gitleaks check of the staged kit: no leaks"

# 3. Regex second net (keys, Google service-account JSON)
if grep -rEn '(AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|sk_(live|test)_[A-Za-z0-9]{10,}|sk-(proj-)?[A-Za-z0-9_-]{30,}|xox[abpr]-[0-9A-Za-z-]{10,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY|"private_key(_id)?"[[:space:]]*:)' "$D"; then
  echo "refusing: secret-like string in kit"; exit 1
fi

# 4. Marketplace rule: no off-platform contact or payment wording in the kit
if grep -rEni '([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|supertea[m]|usdc|\bcrypto(currenc(y|ies))?\b|wallet|bnb chain|paypal|stripe|open an issue|hire me|telegram|whatsapp)' "$D"; then
  echo "refusing: off-platform contact or payment wording in kit (lines above)"; exit 1
fi

rm -f "$OUT"; mkdir -p dist
python3 - "$STAGE" "$OUT" <<'PY'
import os, sys, zipfile
stage, out = sys.argv[1], sys.argv[2]
files = sorted(os.path.relpath(os.path.join(r, f), stage) for r, _, fs in os.walk(stage) for f in fs)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for rel in files:
        full = os.path.join(stage, rel)
        zi = zipfile.ZipInfo(rel, date_time=(2026, 10, 19, 0, 0, 0))   # fixed date: same input, same ZIP
        zi.external_attr = (os.stat(full).st_mode & 0xFFFF) << 16
        zi.create_system = 3  # Unix, so the executable bit on setup.sh survives unzip on Mac/Linux
        zi.compress_type = zipfile.ZIP_DEFLATED
        with open(full, "rb") as fh: z.writestr(zi, fh.read())
PY
unzip -l "$OUT" | tail -n1
sha256sum "$OUT" | cut -d' ' -f1 > "$OUT.sha256"; echo "sha256 $(cat "$OUT.sha256")"
