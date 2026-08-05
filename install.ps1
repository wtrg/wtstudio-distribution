#Requires -Version 5.1
# WTStudio One-Command Installer - v4.05.5
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
$VERSION_TAG = "v4.05.5"
$INSTALL_DIR = "$env:LOCALAPPDATA\WTStudio"
$BIN_DIR     = "$INSTALL_DIR\bin"
$ZIP_NAME    = "WTStudio-Portable-Windows.zip"
$SUM_NAME    = "SHA256SUMS.txt"
$BASE_URL    = "https://github.com/$DIST_REPO/releases/download/$VERSION_TAG"
$ZIP_URL     = "$BASE_URL/$ZIP_NAME"
$SUM_URL     = "$BASE_URL/$SUM_NAME"
$TEMP_ZIP    = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), $ZIP_NAME)
$TEMP_SUM    = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), $SUM_NAME)
$STAGING_DIR = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "WTStudio-Install-Staging")

function Write-Step  { param($n, $msg) Write-Host "[$n] $msg" -ForegroundColor Yellow }
function Write-OK    { param($msg)     Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Warn  { param($msg)     Write-Host "  WARN $msg" -ForegroundColor DarkYellow }
function Write-Fail  { param($msg)     Write-Host "  FAIL $msg" -ForegroundColor Red }

function Remove-TempFiles {
    foreach ($item in @($TEMP_ZIP, $TEMP_SUM, $STAGING_DIR)) {
        if (Test-Path $item) { Remove-Item $item -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-Rollback {
    Write-Warn "Rolling back installation..."
    Remove-TempFiles
    Write-Warn "The existing WTStudio installation was not modified or has been preserved."
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
    Write-Step "1/6" "Downloading WTStudio $VERSION_TAG from GitHub..."
    Invoke-WebRequest -Uri $ZIP_URL -OutFile $TEMP_ZIP -UserAgent "WTStudio-Installer/1.0"
    Invoke-WebRequest -Uri $SUM_URL -OutFile $TEMP_SUM -UserAgent "WTStudio-Installer/1.0"
    Write-OK "Downloaded $ZIP_NAME ($([math]::Round((Get-Item $TEMP_ZIP).Length / 1MB, 1)) MB)"

    # STEP 2: SHA-256 verification (fail-closed)
    Write-Step "2/6" "Verifying SHA-256 checksum..."
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

    # STEP 3: ZIP Manifest Inspection & Staging Extraction
    Write-Step "3/6" "Inspecting ZIP package manifest..."
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($TEMP_ZIP)
    $entryNames = $zipArchive.Entries | ForEach-Object { $_.FullName -replace '\\', '/' }
    $zipArchive.Dispose()

    $hasWebExe = $entryNames | Where-Object { $_ -match '(^|/)wtstudio\.exe$' }
    $hasDesktopExe = $entryNames | Where-Object { $_ -match '(^|/)sp\.exe$' }
    $hasFfmpeg = $entryNames | Where-Object { $_ -match '(^|/)ffmpeg/ffmpeg\.exe$' }
    $hasFfprobe = $entryNames | Where-Object { $_ -match '(^|/)ffmpeg/ffprobe\.exe$' }
    $hasFrontend = $entryNames | Where-Object { $_ -match '(^|/)index\.html$' }

    if (-not $hasWebExe) {
        Write-Fail "The release package is invalid: wtstudio.exe is missing."
        Write-Fail "The existing WTStudio installation was not modified."
        Remove-TempFiles
        exit 1
    }
    if (-not $hasDesktopExe -or -not $hasFfmpeg -or -not $hasFfprobe -or -not $hasFrontend) {
        Write-Fail "The release package is incomplete or corrupted."
        Write-Fail "The existing WTStudio installation was not modified."
        Remove-TempFiles
        exit 1
    }
    Write-OK "ZIP manifest verified (wtstudio.exe, sp.exe, ffmpeg, frontend assets present)"

    # Extract to Staging
    if (Test-Path $STAGING_DIR) { Remove-Item $STAGING_DIR -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $STAGING_DIR -Force | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($TEMP_ZIP, $STAGING_DIR)

    # Detect bundle root within staging
    $sourceRoot = $STAGING_DIR
    $subWtExe = Get-ChildItem -Path $STAGING_DIR -Filter "wtstudio.exe" -Recurse | Select-Object -First 1
    if ($subWtExe) {
        $sourceRoot = $subWtExe.Directory.FullName
    }

    # Verify staged files
    if (-not (Test-Path "$sourceRoot\wtstudio.exe") -or -not (Test-Path "$sourceRoot\sp.exe")) {
        Write-Fail "Staged payload validation failed."
        Remove-TempFiles
        exit 1
    }

    # STEP 4: Stop running processes & Upgrade Cleanup
    Write-Step "4/6" "Stopping processes and cleaning previous runtime..."
    $stateFile = "$INSTALL_DIR\runtime\server.json"
    if (Test-Path $stateFile) {
        try {
            $wtExe = "$INSTALL_DIR\wtstudio.exe"
            if (Test-Path $wtExe) { & "$wtExe" stop | Out-Null }
        } catch {}
    }
    Get-Process -Name "sp" -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 400

    New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
    New-Item -ItemType Directory -Path $BIN_DIR -Force | Out-Null

    # Allowlist of runtime bundle items to clean (preserving user data / license)
    $runtimeItems = @(
        "$INSTALL_DIR\_internal",
        "$INSTALL_DIR\wtstudio.exe",
        "$INSTALL_DIR\sp.exe",
        "$INSTALL_DIR\ffmpeg",
        "$INSTALL_DIR\studio_web",
        "$INSTALL_DIR\web",
        "$INSTALL_DIR\law.txt",
        "$INSTALL_DIR\LICENSE",
        "$INSTALL_DIR\THIRD_PARTY_NOTICES.md"
    )
    foreach ($item in $runtimeItems) {
        if (Test-Path $item) { Remove-Item $item -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # Copy new bundle items to installation directory
    Get-ChildItem -Path $sourceRoot | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $INSTALL_DIR -Recurse -Force
    }
    Write-OK "Copied new WTStudio runtime to $INSTALL_DIR"

    # STEP 5: Create wtstudio shims
    Write-Step "5/6" "Generating command shims..."
    $webExePath = "$INSTALL_DIR\wtstudio.exe"
    $desktopExePath = "$INSTALL_DIR\sp.exe"

    if (-not (Test-Path -LiteralPath $webExePath)) {
        throw "wtstudio.exe was not installed."
    }
    if (-not (Test-Path -LiteralPath $desktopExePath)) {
        throw "sp.exe was not installed."
    }

    $cmdContent = "@echo off`r`n`"$INSTALL_DIR\wtstudio.exe`" %*"
    Set-Content -Path "$BIN_DIR\wtstudio.cmd" -Value $cmdContent -Encoding ASCII

    $ps1Content = "& `"$env:LOCALAPPDATA\WTStudio\wtstudio.exe`" @args"
    Set-Content -Path "$BIN_DIR\wtstudio.ps1" -Value $ps1Content -Encoding ASCII
    Write-OK "Created wtstudio.cmd and wtstudio.ps1 in $BIN_DIR"

    # STEP 6: Update User PATH
    Write-Step "6/6" "Updating User PATH..."
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
    Write-Host "To open the desktop app, run:" -ForegroundColor White
    Write-Host "    wtstudio desktop" -ForegroundColor Cyan
    Write-Host ""

} catch {
    Write-Fail $_.Exception.Message
    Invoke-Rollback
}
