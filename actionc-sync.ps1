<#
.SYNOPSIS
Sync the Tizen Action Compiler schema data (actions\, entities\, action.seq)
with the tizen-action version installed on the attached device.

.DESCRIPTION
The compiler binaries (actionc, action2tidl, tidlc) are reused as installed;
only the schema data is fetched, from the git repository named in
data-repo.conf, and installed into %USERPROFILE%\.action-tools\data where
actionc reads it. Windows counterpart of actionc-sync.sh; run it through
actionc-sync.bat.

Version matching: the directory named exactly like the device version is used
when it exists; otherwise the highest version with the same <major>.<minor>
that is not newer than the device.

.PARAMETER Target
Sync to this tizen-action version instead of the one in data-repo.conf
(DATA_VERSION) or on the device.
.PARAMETER List
List the versions available in the data repository.
.PARAMETER DataDir
Install the schemas into this directory instead of %USERPROFILE%\.action-tools\data.
.PARAMETER Offline
Do not contact the repository; reuse the last fetch.
.PARAMETER Quiet
Only print warnings and errors.

Environment: SDB_SERIAL, ACTIONC_DATA_REPO, ACTIONC_DATA_REPO_BRANCH,
ACTIONC_DATA_VERSION (see data-repo.conf). The version to sync to is taken from,
in order: -Target, ACTIONC_DATA_VERSION, DATA_VERSION in data-repo.conf, and
finally the attached device over sdb.
#>
[CmdletBinding()]
param(
  [Alias('t')][string]$Target = '',
  [Alias('l')][switch]$List,
  [Alias('d')][string]$DataDir = '',
  [Alias('o')][switch]$Offline,
  [Alias('q')][switch]$Quiet
)

# 'Continue' on purpose: with 'Stop', Windows PowerShell 5.1 turns any stderr
# line of a native command (git, sdb) into a terminating error. Exit codes are
# checked explicitly and file operations pass -ErrorAction Stop.
$ErrorActionPreference = 'Continue'
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir = Join-Path $env:USERPROFILE '.action-tools'
$CacheDir   = Join-Path $InstallDir 'data-repo'
$DataDirSet = $DataDir -ne ''
if (-not $DataDirSet) { $DataDir = Join-Path $InstallDir 'data' }

function Log($msg)  { if (-not $Quiet) { Write-Host $msg } }
function Warn($msg) { Write-Host "warning: $msg" -ForegroundColor Yellow }
function Die($msg)  { Write-Host "error: $msg" -ForegroundColor Red; exit 1 }

# --- Configuration -------------------------------------------------------
$DataRepo = ''
$DataRepoBranch = 'main'
$DataVersion = ''
$ConfFile = @((Join-Path $InstallDir 'data-repo.conf'), (Join-Path $ScriptDir 'data-repo.conf')) |
            Where-Object { Test-Path $_ } | Select-Object -First 1
if ($ConfFile) {
  foreach ($line in Get-Content $ConfFile) {
    $line = $line.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { continue }
    $kv = $line -split '=', 2
    if ($kv.Count -ne 2) { continue }
    switch ($kv[0].Trim()) {
      'DATA_REPO'        { $DataRepo = $kv[1].Trim() }
      'DATA_REPO_BRANCH' { $DataRepoBranch = $kv[1].Trim() }
      'DATA_VERSION'     { $DataVersion = $kv[1].Trim() }
    }
  }
}
if ($env:ACTIONC_DATA_REPO)        { $DataRepo = $env:ACTIONC_DATA_REPO }
if ($env:ACTIONC_DATA_REPO_BRANCH) { $DataRepoBranch = $env:ACTIONC_DATA_REPO_BRANCH }
$DataVersionSource = $ConfFile
if ($env:ACTIONC_DATA_VERSION)     { $DataVersion = $env:ACTIONC_DATA_VERSION; $DataVersionSource = 'ACTIONC_DATA_VERSION' }
if ($DataVersion -eq 'auto') { $DataVersion = '' }
if (-not $DataRepo) { Die 'no data repository configured (DATA_REPO in data-repo.conf or ACTIONC_DATA_REPO)' }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Die 'git is required to fetch the schema data' }

# --- Fetch the data repository -------------------------------------------
function Git-Cache { git -C $CacheDir @args 2>$null }

$HasCache = Test-Path (Join-Path $CacheDir '.git')
if ($HasCache) {
  $haveUrl    = (Git-Cache config --get remote.origin.url) -join ''
  $haveBranch = (Git-Cache rev-parse --abbrev-ref HEAD) -join ''
  if ($haveUrl -ne $DataRepo -or $haveBranch -ne $DataRepoBranch) {
    Log 'Data repository changed; re-fetching.'
    Remove-Item -Recurse -Force $CacheDir -ErrorAction Stop
    $HasCache = $false
  }
}

if ($Offline) {
  if (-not $HasCache) { Die 'no previously fetched data to use offline' }
  Log "Offline: using data fetched $((Git-Cache log -1 --format=%cd --date=short) -join '')."
} elseif ($HasCache) {
  Log "Fetching $DataRepo ($DataRepoBranch)..."
  git -C $CacheDir fetch --quiet --depth 1 origin $DataRepoBranch 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0) {
    git -C $CacheDir checkout --quiet -B $DataRepoBranch FETCH_HEAD 2>&1 | Out-Null
  } else {
    Warn "fetch failed; using data fetched $((Git-Cache log -1 --format=%cd --date=short) -join '')."
  }
} else {
  New-Item -ItemType Directory -Force $InstallDir -ErrorAction Stop | Out-Null
  Log "Cloning $DataRepo ($DataRepoBranch)..."
  git clone --quiet --depth 1 --branch $DataRepoBranch $DataRepo $CacheDir 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Die "could not clone $DataRepo. Check network access and credentials, or set ACTIONC_DATA_REPO." }
}

# Versions published in the repository, oldest first.
$Available = @(Get-ChildItem -Directory $CacheDir |
  Where-Object { $_.Name -match '^[0-9]+(\.[0-9]+)+$' -and (Test-Path (Join-Path $_.FullName 'actions')) } |
  ForEach-Object { $_.Name } | Sort-Object { [version]$_ })

if ($List) {
  Write-Host "Schema data versions in $DataRepo ($DataRepoBranch):"
  $Available | ForEach-Object { Write-Host "  $_" }
  exit 0
}

# --- Target version (option, then conf/env, then the device over sdb) -----
if (-not $Target -and $DataVersion) {
  $Target = $DataVersion
  Log "Pinned tizen-action version: $Target ($DataVersionSource)"
}
if (-not $Target) {
  if (-not (Get-Command sdb -ErrorAction SilentlyContinue)) { Die 'sdb not found; pass -Target VERSION to choose the tizen-action version' }
  $sdbArgs = @()
  if ($env:SDB_SERIAL) {
    $sdbArgs = @('-s', $env:SDB_SERIAL)
  } else {
    $count = @(sdb devices 2>$null | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice\s' }).Count
    if ($count -eq 0) { Die 'no device connected; pass -Target VERSION to choose the tizen-action version' }
    if ($count -gt 1) { Die "$count devices connected; set SDB_SERIAL or pass -Target VERSION" }
  }
  $out = (& sdb @sdbArgs shell "rpm -q --qf '%{VERSION}' tizen-action" 2>$null) -join "`n"
  $Target = ($out -split "`r?`n" | Select-Object -First 1).Trim()
  # rpm reports a missing package as prose on stdout, so require a leading digit.
  if ($Target -notmatch '^[0-9]') { Die 'could not read the tizen-action version from the device (is it reachable and is tizen-action installed?)' }
  Log "Device tizen-action version: $Target"
}
if ($Target -notmatch '^[0-9]+(\.[0-9]+)+$') { Die "invalid version '$Target'" }

# --- Pick the matching data version --------------------------------------
$Chosen = ''
$TargetMM = $Target.Substring(0, $Target.LastIndexOf('.'))
foreach ($v in $Available) {
  if ($v -eq $Target) { $Chosen = $v; break }
  $vMM = $v.Substring(0, $v.LastIndexOf('.'))
  if ($vMM -eq $TargetMM -and [version]$v -le [version]$Target) { $Chosen = $v }  # ascending, last hit is highest
}
if (-not $Chosen) {
  Write-Host "error: no schema data for tizen-action $Target in $DataRepo." -ForegroundColor Red
  Write-Host '       available versions:'
  $Available | ForEach-Object { Write-Host "         $_" }
  exit 1
}
if ($Chosen -ne $Target) { Log "No exact match for $Target; using $Chosen (same $TargetMM.x line)." }

# Byte-for-byte file comparison through .NET. Get-FileHash is avoided on
# purpose: it needs PowerShell 4+, and it is also missing when powershell.exe
# is started from PowerShell 7 (inherited PSModulePath breaks the autoload of
# Microsoft.PowerShell.Utility). -ceq because Base64 is case-sensitive.
function Same-Content($a, $b) {
  [Convert]::ToBase64String([IO.File]::ReadAllBytes($a)) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($b))
}

# --- Install into the data directory --------------------------------------
$Src = Join-Path $CacheDir $Chosen
$VersionFile = Join-Path $DataDir 'DATA_VERSION'
$UpToDate = $false
if ((Test-Path $VersionFile) -and ((Get-Content $VersionFile -Raw).Trim() -eq $Chosen)) {
  $srcFiles = @(Get-ChildItem -Recurse -File $Src | ForEach-Object { $_.FullName.Substring($Src.Length) })
  $dstFiles = @(Get-ChildItem -Recurse -File $DataDir | Where-Object { $_.Name -notin 'DATA_VERSION','DATA_SOURCE' } |
                ForEach-Object { $_.FullName.Substring($DataDir.Length) })
  if ($srcFiles.Count -gt 0 -and $srcFiles.Count -eq $dstFiles.Count -and -not (Compare-Object $srcFiles $dstFiles)) {
    $UpToDate = $true
    foreach ($rel in $srcFiles) {
      if (-not (Same-Content (Join-Path $Src $rel) (Join-Path $DataDir $rel))) { $UpToDate = $false; break }
    }
  }
}

if ($UpToDate) {
  Log "Schema data $Chosen already installed in $DataDir."
} else {
  # Refusing to wipe an arbitrary directory: only the compiler's own data dir
  # or an explicitly requested one is replaced.
  if ((Test-Path $DataDir) -and -not $DataDirSet -and $DataDir -ne (Join-Path $InstallDir 'data')) {
    Die "refusing to replace $DataDir; pass -DataDir to confirm"
  }
  $Tmp = "$DataDir.sync.$PID"
  if (Test-Path $Tmp) { Remove-Item -Recurse -Force $Tmp -ErrorAction Stop }
  New-Item -ItemType Directory -Force (Split-Path -Parent $DataDir) -ErrorAction Stop | Out-Null
  Copy-Item -Recurse $Src $Tmp -ErrorAction Stop
  Set-Content -Path (Join-Path $Tmp 'DATA_VERSION') -Value $Chosen -ErrorAction Stop
  $rev = (Git-Cache rev-parse --short HEAD) -join ''
  Set-Content -Path (Join-Path $Tmp 'DATA_SOURCE') -Value "$DataRepo $DataRepoBranch $rev" -ErrorAction Stop
  if (Test-Path $DataDir) { Remove-Item -Recurse -Force $DataDir -ErrorAction Stop }
  Move-Item $Tmp $DataDir -ErrorAction Stop
  $nA = @(Get-ChildItem -File (Join-Path $DataDir 'actions')).Count
  $nE = @(Get-ChildItem -File (Join-Path $DataDir 'entities')).Count
  Log "Installed schema data $Chosen into $DataDir ($nA actions, $nE entities)."
}

if ($env:ACTIONC_DATA_DIR -and $env:ACTIONC_DATA_DIR -ne $DataDir) {
  Warn "ACTIONC_DATA_DIR=$($env:ACTIONC_DATA_DIR) points elsewhere; actionc will not read $DataDir."
}
