<#
Nyyo scraper kit - scrape public pages into CSV + JSON (+ your Google Sheet) on your own computer (Windows).
Free 1-click install kit, MIT licence. Nyyo Automation.

  powershell -ExecutionPolicy Bypass -File .\setup.ps1              first run: creates config\scrape.toml, installs, scrapes the example site
  powershell -ExecutionPolicy Bypass -File .\setup.ps1 -Check       check the config and robots.txt, scrape nothing
  powershell -ExecutionPolicy Bypass -File .\setup.ps1 -Target books -MaxPages 1

Options: -Native (no Docker, Python venv), -Browser (pages that need JavaScript), -NoOpen
Safe to run again: your config is never overwritten, installs are reused, outputs are replaced
atomically (previous file kept as *.previous.csv), and an empty result never replaces a good one.
Works with Windows PowerShell 5.1 and PowerShell 7 (also on Mac / Linux).
#>
param(
  [switch]$Native, [switch]$Browser, [switch]$NoOpen, [switch]$Check,
  [string[]]$Target = @(), [int]$MaxPages = 0
)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$KitVersion = '1.0.0'
$KitDir = Split-Path -Parent $MyInvocation.MyCommand.Path
function Say($m)  { Write-Host "==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "[x] $m" -ForegroundColor Red; exit 3 }
$OnWindows = ($env:OS -eq 'Windows_NT')

if (-not (Test-Path (Join-Path $KitDir 'scraper/nyyo_scrape.py')) -or -not (Test-Path (Join-Path $KitDir 'requirements.txt'))) {
  Die 'Kit files missing: run this script from the unzipped kit folder.' }
Set-Location $KitDir
foreach ($d in 'output', 'credentials') { New-Item -ItemType Directory -Force -Path (Join-Path $KitDir $d) | Out-Null }
$Config = Join-Path $KitDir 'config/scrape.toml'

# ---- 1. Your config (created once, never overwritten) ----
if (-not (Test-Path $Config)) {
  Copy-Item (Join-Path $KitDir 'config/scrape.example.toml') $Config
  Say 'Created config\scrape.toml from the example (scrapes the books.toscrape.com practice site).'
  Say 'Edit it later to set your own URLs and columns, then run setup.ps1 again.'
}
if (-not $Browser -and (Select-String -Path $Config -Pattern '^\s*render\s*=\s*"browser"' -Quiet)) {
  Warn 'A target uses render = "browser": add -Browser so the browser add-on is installed.' }

$Pass = @()
if ($Check) { $Pass += '--check' }
foreach ($t in $Target) { $Pass += @('--target', $t) }
if ($MaxPages -gt 0) { $Pass += @('--max-pages', "$MaxPages") }

# ---- 2. Engine: Docker (preferred) or a Python virtual environment ----
$Engine = ''
$HasDocker = [bool](Get-Command docker -ErrorAction SilentlyContinue)
if (-not $Native -and $HasDocker) {
  & docker info *> $null
  if ($LASTEXITCODE -eq 0) { $Engine = 'docker' }
  else { Warn 'Docker is installed but not running (start Docker Desktop to use it). Using Python instead.' }
}
if (-not $Engine) {
  if (-not $Native -and -not $HasDocker) { Warn 'Docker not found. Using Python instead (no Docker needed).' }
  $Engine = 'native'
}

$Req = 'requirements.txt'; $Suffix = ''; $Msg = 'about 1 minute'
if ($Browser) { $Req = 'requirements-browser.txt'; $Suffix = '-browser'; $Msg = 'about 5 minutes, browser add-on included' }
$bytes = [IO.File]::ReadAllBytes((Join-Path $KitDir 'Dockerfile')) + [IO.File]::ReadAllBytes((Join-Path $KitDir $Req))
$sha = [Security.Cryptography.SHA256]::Create()
$DepsHash = (($sha.ComputeHash([byte[]]$bytes) | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 16)

if ($Engine -eq 'docker') {
  $Tag = "nyyo-scraper-kit:$KitVersion$Suffix"
  $Have = (& docker image inspect -f '{{index .Config.Labels "nyyo.deps"}}' $Tag 2>$null)
  if ("$Have".Trim() -eq $DepsHash) { Say "Scraper image $Tag already installed." }
  else {
    Say "Building the scraper image $Tag (first time only: $Msg)..."
    $b = '0'; if ($Browser) { $b = '1' }
    & docker build -q --build-arg "BROWSER=$b" --label "nyyo.deps=$DepsHash" -t $Tag . | Out-Null
    if ($LASTEXITCODE -ne 0) { Die 'Docker could not build the image. Check your internet connection, then run setup.ps1 again.' }
    Say 'Image ready (Python 3.12, packages pinned by hash).'
  }
  $RunArgs = @('run', '--rm', '--init')
  if (-not $OnWindows) { $RunArgs += @('--user', "$(& id -u):$(& id -g)") }
  if ($env:NYYO_DOCKER_NETWORK) { $RunArgs += @('--network', $env:NYYO_DOCKER_NETWORK) }
  $RunArgs += @('-e', 'HOME=/tmp', '-e', 'NYYO_IN_DOCKER=1',
    '-v', "$(Join-Path $KitDir 'scraper'):/kit/scraper:ro", '-v', "$(Join-Path $KitDir 'config'):/kit/config:ro",
    '-v', "$(Join-Path $KitDir 'credentials'):/kit/credentials:ro", '-v', "$(Join-Path $KitDir 'output'):/kit/output",
    $Tag, '--config', '/kit/config/scrape.toml') + $Pass
  & docker @RunArgs
  $RC = $LASTEXITCODE
} else {
  $Py = $null
  $cands = @(@('py', '-3'), @('python'), @('python3'))
  foreach ($c in $cands) {
    if (Get-Command $c[0] -ErrorAction SilentlyContinue) {
      $extra = @(); if ($c.Count -gt 1) { $extra = $c[1..($c.Count - 1)] }
      & $c[0] @extra -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' *> $null
      if ($LASTEXITCODE -eq 0) { $Py = $c; break }
    }
  }
  if (-not $Py) { Die 'Python 3.9 or newer is needed (or install Docker Desktop). See INSTALL.md, Step 1.' }
  $PyExe = $Py[0]; $PyArgs = @(); if ($Py.Count -gt 1) { $PyArgs = $Py[1..($Py.Count - 1)] }
  if ($Browser) {
    & $PyExe @PyArgs -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' *> $null
    if ($LASTEXITCODE -ne 0) { Die 'The browser add-on needs Python 3.10 or newer. Install a newer Python or use Docker.' }
  }
  $Venv = Join-Path $KitDir '.venv'
  if ($OnWindows) { $VPy = Join-Path $Venv 'Scripts\python.exe' } else { $VPy = Join-Path $Venv 'bin/python' }
  if (-not (Test-Path $VPy)) {
    Say 'Creating a private Python environment in .venv...'
    & $PyExe @PyArgs -m venv $Venv
    if ($LASTEXITCODE -ne 0) { Die 'Could not create the Python environment.' }
  }
  $Stamp = Join-Path $Venv '.nyyo-deps'
  if ((Test-Path $Stamp) -and ((Get-Content $Stamp -Raw).Trim() -eq $DepsHash)) { Say 'Python packages already installed.' }
  else {
    Say 'Installing pinned Python packages (checked by hash)...'
    & $VPy -m pip install -q --disable-pip-version-check --require-hashes -r $Req
    if ($LASTEXITCODE -ne 0) { Die 'Package install failed. Check your internet connection and run again.' }
    if ($Browser) {
      Say 'Installing the Chromium browser for JavaScript pages...'
      & $VPy -m playwright install chromium
      if ($LASTEXITCODE -ne 0) { Die 'Chromium download failed. Check your internet connection and run again.' }
    }
    Set-Content -Path $Stamp -Value $DepsHash -NoNewline
  }
  & $VPy (Join-Path $KitDir 'scraper/nyyo_scrape.py') --config $Config @Pass
  $RC = $LASTEXITCODE
}

Write-Host ''
$Out = Join-Path $KitDir 'output'
switch ($RC) {
  0 { Say "Finished. Your files: $Out" }
  1 { Warn "Finished with warnings (see [!] lines above). Your files: $Out" }
  2 { Warn 'No rows for at least one target: check the selectors in config\scrape.toml (INSTALL.md, Troubleshooting).' }
  3 { Die 'Fix config\scrape.toml (see the message above) and run setup.ps1 again.' }
  default { Write-Host "[x] The scraper stopped with an error (code $RC). See INSTALL.md, Troubleshooting." -ForegroundColor Red }
}
if (-not $NoOpen -and $OnWindows -and $RC -lt 3) { Start-Process explorer.exe $Out }
exit $RC
