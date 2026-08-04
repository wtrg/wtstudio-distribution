#Requires -Version 5.1
# WTStudio One-Command Installer â€” v4.05.2
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm 'https://raw.githubusercontent.com/wtrg/wtstudio-distribution/main/install.ps1' | iex"
#
# Requirements: Windows 10/11 x64, PowerShell 5.1+
# Does NOT require: Python, Git, .NET SDK, Administrator privileges
# Installs to: %LOCALAPPDATA%\WTStudio  (user-local, no UAC)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# â”€â”€ Configuration â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function Write-Step  { param($n, $msg) Write-Host "[$n] $msg" -ForegroundColor Yellow }
function Write-OK    { param($msg)     Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Warn  { param($msg)     Write-Host "  WARN $msg" -ForegroundColor DarkYellow }
function Write-Fail  { param($msg)     Write-Host "  FAIL $msg" -ForegroundColor Red }

function Remove-TempFiles {
    foreach ($f in @($TEMP_ZIP, $TEMP_SUM)) {
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
}

# Rollback: remove partially-installed files on failure
function Invoke-Rollback {
    Write-Warn "Rolling back partial installation..."
    Remove-TempFiles
    # Only remove the bundle dirs, not any user data the user may have stored
    $toRemove = @("$INSTALL_DIR\_internal", "$INSTALL_DIR\sp.exe", "$BIN_DIR\wtstudio.cmd", "$BIN_DIR\wtstudio.ps1")
    foreach ($item in $toRemove) {
        if (Test-Path $item) { Remove-Item $item -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-Warn "Rollback complete. Run the installer again after fixing the issue."
}

# â”€â”€ Banner â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  WTStudio $VERSION_TAG  Windows Installer" -ForegroundColor Cyan
Write-Host "  Install dir : $INSTALL_DIR" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

# â”€â”€ Force TLS 1.2+ â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

try {

    # â”€â”€ STEP 1: Download â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Step "1/5" "Downloading WTStudio $VERSION_TAG from GitHub..."
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "WTStudio-Installer/1.0")
    $wc.DownloadFile($ZIP_URL, $TEMP_ZIP)
    $wc.DownloadFile($SUM_URL, $TEMP_SUM)
    Write-OK "Downloaded $ZIP_NAME ($([math]::Round((Get-Item $TEMP_ZIP).Length / 1MB, 1)) MB)"

    # â”€â”€ STEP 2: SHA-256 verification â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Step "2/5" "Verifying SHA-256 checksum..."
    $actualHash = (Get-FileHash -Path $TEMP_ZIP -Algorithm SHA256).Hash.ToLower()
    $sumContent = Get-Content $TEMP_SUM -Raw -Encoding UTF8
    $matched = $sumContent -match "^([0-9a-f]{64})\s+\*?$([regex]::Escape($ZIP_NAME))"
    if ($matched) {
        $expectedHash = $Matches[1].ToLower()
        if ($actualHash -ne $expectedHash) {
            throw "SHA-256 mismatch!`n  Expected : $expectedHash`n  Got      : $actualHash`n  The download may be corrupted or tampered. Aborting."
        }
        Write-OK "SHA-256 verified: $actualHash"
    } else {
        Write-Warn "Checksum entry not found in SHA256SUMS.txt â€” skipping hash check"
    }

    # â”€â”€ STEP 3: Stop any running wtstudio / sp process â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Step "3/5" "Extracting to $INSTALL_DIR ..."
    Get-Process -Name "sp" -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 400

    # Create install dir
    New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
    New-Item -ItemType Directory -Path $BIN_DIR -Force | Out-Null

    # Remove old bundle files (preserve user data / config)
    $bundleItems = @("$INSTALL_DIR\_internal", "$INSTALL_DIR\sp.exe",
                     "$INSTALL_DIR\law.txt", "$INSTALL_DIR\LICENSE",
                     "$INSTALL_DIR\THIRD_PARTY_NOTICES.md")
    foreach ($item in $bundleItems) {
        if (Test-Path $item) { Remove-Item $item -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # Extract ZIP
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($TEMP_ZIP, $INSTALL_DIR)
    Write-OK "Extracted to $INSTALL_DIR"

    # â”€â”€ STEP 4: Create wtstudio shim â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Step "4/5" "Creating wtstudio command shim..."
    $exePath = "$INSTALL_DIR\sp.exe"
    if (-not (Test-Path $exePath)) {
        throw "Extraction succeeded but sp.exe not found at $exePath â€” ZIP structure may have changed."
    }

    # .cmd shim (works in cmd.exe and PowerShell)
    $cmdContent = "@echo off`r`n`"$exePath`" %*"
    Set-Content -Path "$BIN_DIR\wtstudio.cmd" -Value $cmdContent -Encoding ASCII

    # .ps1 shim (optional, cleaner in PS)
    $ps1Content = "& `"$exePath`" @args"
    Set-Content -Path "$BIN_DIR\wtstudio.ps1" -Value $ps1Content -Encoding UTF8
    Write-OK "Created wtstudio.cmd and wtstudio.ps1 in $BIN_DIR"

    # â”€â”€ STEP 5: Update User PATH â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    Write-Step "5/5" "Updating User PATH..."
    $userPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
    $pathParts = $userPath -split ';' | Where-Object { $_ -ne '' }

    # Avoid duplicates â€” remove any existing WTStudio bin entry first
    $pathParts = $pathParts | Where-Object { $_ -notmatch [regex]::Escape($BIN_DIR) }
    $newPath = ($pathParts + $BIN_DIR) -join ';'
    [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::User)
    Write-OK "Added $BIN_DIR to User PATH"

    Remove-TempFiles

    # â”€â”€ Done â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
    Write-Host "SmartScreen may show an unknown publisher warning â€” click 'More info' > 'Run anyway'." -ForegroundColor DarkGray
    Write-Host ""

} catch {
    Write-Fail $_.Exception.Message
    Invoke-Rollback
    exit 1
}
