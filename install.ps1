#Requires -Version 5.1
# WTStudio One-Command Installer - v4.05.2
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm 'https://raw.githubusercontent.com/wtrg/wtstudio-distribution/main/install.ps1' | iex"
#
# Requirements: Windows 10/11 x64, PowerShell 5.1+
# Does NOT require: Python, Git, .NET SDK, Administrator privileges
# Installs to: %LOCALAPPDATA%\WTStudio  (user-local, no UAC)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Configuration
$DIST_REPO   = "wtrg/wtstudio-distribution"
$VERSION_TAG = "v4.05.2"
$INSTALL_DIR = "$env:LOCALAPPDATA\WTStudio"
$BIN_DIR     = "$INSTALL_DIR\bin"
$ZIP_NAME    = "WTStudio-Portable-Windows.zip"
$SUM_NAME    = "SHA256SUMS.txt"
$BASE_URL    = "https://github.com/$DIST_REPO/releases/download/$VERSION_TAG"
$ZIP_URL     = "$BASE_URL/$ZIP_NAME"
$SUM_URL     = "$BASE_URL/$SUM_NAME"
$TEMP_ZIP    = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), $ZIP_NAME)
$TEMP_SUM    = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), $SUM_NAME)

function Write-Step  { param($n, $msg) Write-Host "[$n] $msg" -ForegroundColor Yellow }
function Write-OK    { param($msg)     Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Warn  { param($msg)     Write-Host "  WARN $msg" -ForegroundColor DarkYellow }
function Write-Fail  { param($msg)     Write-Host "  FAIL $msg" -ForegroundColor Red }

function Remove-TempFiles {
    foreach ($f in @($TEMP_ZIP, $TEMP_SUM)) {
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-Rollback {
    Write-Warn "Rolling back partial installation..."
    Remove-TempFiles
    $toRemove = @("$INSTALL_DIR\_internal", "$INSTALL_DIR\sp.exe", "$BIN_DIR\wtstudio.cmd", "$BIN_DIR\wtstudio.ps1")
    foreach ($item in $toRemove) {
        if (Test-Path $item) { Remove-Item $item -Recurse -Force -ErrorAction SilentlyContinue }
    }
    # Remove PATH entry if added
    $userPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
    if ($userPath -match [regex]::Escape($BIN_DIR)) {
        $newPath = ($userPath -split ';' | Where-Object { $_ -notmatch [regex]::Escape($BIN_DIR) }) -join ';'
        [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::User)
    }
    Write-Warn "Rollback complete."
    exit 1
}

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  WTStudio $VERSION_TAG  Windows Installer" -ForegroundColor Cyan
Write-Host "  Install dir : $INSTALL_DIR" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

try {
    # STEP 1: Download
    Write-Step "1/5" "Downloading WTStudio $VERSION_TAG from GitHub..."
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "WTStudio-Installer/1.0")
    $wc.DownloadFile($ZIP_URL, $TEMP_ZIP)
    $wc.DownloadFile($SUM_URL, $TEMP_SUM)
    Write-OK "Downloaded $ZIP_NAME ($([math]::Round((Get-Item $TEMP_ZIP).Length / 1MB, 1)) MB)"

    # STEP 2: SHA-256 verification (fail-closed)
    Write-Step "2/5" "Verifying SHA-256 checksum..."
    $actualHash = (Get-FileHash -Path $TEMP_ZIP -Algorithm SHA256).Hash.ToLower()

    if (-not (Test-Path $TEMP_SUM)) {
        Write-Fail "Failed to download SHA256SUMS.txt"
        Remove-TempFiles
        exit 1
    }

    $sumContent = Get-Content $TEMP_SUM -Raw -Encoding UTF8
    $matched = $sumContent -match "^([0-9a-f]{64})\s+\*?$([regex]::Escape($ZIP_NAME))"

    if (-not $matched) {
        Write-Fail "Checksum entry not found in SHA256SUMS.txt - aborting"
        Remove-TempFiles
        exit 1
    }

    $expectedHash = $Matches[1].ToLower()
    if ($actualHash -ne $expectedHash) {
        Write-Fail "SHA-256 mismatch!"
        Write-Fail "  Expected : $expectedHash"
        Write-Fail "  Got      : $actualHash"
        Write-Fail "The download may be corrupted or tampered. Aborting."
        Remove-TempFiles
        exit 1
    }
    Write-OK "SHA-256 verified: $actualHash"

    # STEP 3: Extract
    Write-Step "3/5" "Extracting to $INSTALL_DIR ..."
    Get-Process -Name "sp" -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 400

    New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
    New-Item -ItemType Directory -Path $BIN_DIR -Force | Out-Null

    $bundleItems = @("$INSTALL_DIR\_internal", "$INSTALL_DIR\sp.exe",
                     "$INSTALL_DIR\law.txt", "$INSTALL_DIR\LICENSE",
                     "$INSTALL_DIR\THIRD_PARTY_NOTICES.md")
    foreach ($item in $bundleItems) {
        if (Test-Path $item) { Remove-Item $item -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($TEMP_ZIP, $INSTALL_DIR)
    Write-OK "Extracted to $INSTALL_DIR"

    # STEP 4: Create wtstudio shim
    Write-Step "4/5" "Creating wtstudio command shim..."
    $exePath = "$INSTALL_DIR\sp.exe"
    if (-not (Test-Path $exePath)) {
        throw "Extraction succeeded but sp.exe not found at $exePath - ZIP structure may have changed."
    }

    $cmdContent = "@echo off`r`n`"$exePath`" %*"
    Set-Content -Path "$BIN_DIR\wtstudio.cmd" -Value $cmdContent -Encoding ASCII

    $ps1Content = "& `"$exePath`" @args"
    Set-Content -Path "$BIN_DIR\wtstudio.ps1" -Value $ps1Content -Encoding UTF8
    Write-OK "Created wtstudio.cmd and wtstudio.ps1 in $BIN_DIR"

    # STEP 5: Update User PATH
    Write-Step "5/5" "Updating User PATH..."
    $userPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
    $pathParts = $userPath -split ';' | Where-Object { $_ -ne '' }
    $pathParts = $pathParts | Where-Object { $_ -notmatch [regex]::Escape($BIN_DIR) }
    $newPath = ($pathParts + $BIN_DIR) -join ';'
    [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::User)
    Write-OK "Added $BIN_DIR to User PATH"

    Remove-TempFiles

    Write-Host ""
    Write-Host "=====================================================" -ForegroundColor Green
    Write-Host "  WTStudio $VERSION_TAG installed successfully!" -ForegroundColor Green
    Write-Host "=====================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Open a NEW terminal and run:" -ForegroundColor White
    Write-Host ""
    Write-Host "    wtstudio" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "First run will ask for license activation." -ForegroundColor DarkGray
    Write-Host "SmartScreen may show an unknown publisher warning." -ForegroundColor DarkGray
    Write-Host "Click 'More info' then 'Run anyway' if prompted." -ForegroundColor DarkGray
    Write-Host ""

} catch {
    Write-Fail $_.Exception.Message
    Invoke-Rollback
}