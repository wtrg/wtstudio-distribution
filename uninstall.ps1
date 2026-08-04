#Requires -Version 5.1
# WTStudio Uninstaller
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1
#
# Safe to run multiple times (idempotent).
# Does NOT delete user project files or video output.
# Does NOT delete license activation data unless -PurgeLicense is passed.

param(
    [switch]$PurgeLicense = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$INSTALL_DIR = "$env:LOCALAPPDATA\WTStudio"
$BIN_DIR     = "$INSTALL_DIR\bin"

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  WTStudio Uninstaller" -ForegroundColor Cyan
Write-Host "  Install dir : $INSTALL_DIR" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Stop running sp.exe processes
Write-Host "[1/4] Stopping WTStudio processes..." -ForegroundColor Yellow
$procs = Get-Process -Name "sp" -ErrorAction SilentlyContinue
if ($procs) {
    $procs | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        Write-Host "  Stopped PID $($_.Id)"
    }
    Start-Sleep -Milliseconds 600
} else {
    Write-Host "  No running sp.exe processes found."
}

# 2. Remove installation bundle
Write-Host "[2/4] Removing WTStudio installation files..." -ForegroundColor Yellow
if (Test-Path -LiteralPath $INSTALL_DIR) {
    Get-ChildItem -LiteralPath $INSTALL_DIR -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            try { $_.Attributes = [System.IO.FileAttributes]::Normal } catch {}
        }
    Remove-Item -LiteralPath $INSTALL_DIR -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $INSTALL_DIR)) {
        Write-Host "  OK  Removed $INSTALL_DIR" -ForegroundColor Green
    } else {
        Write-Host "  WARN Some files in $INSTALL_DIR could not be removed (may be in use)." -ForegroundColor DarkYellow
    }
} else {
    Write-Host "  $INSTALL_DIR does not exist - nothing to remove."
}

# 3. Clean User PATH
Write-Host "[3/4] Removing $BIN_DIR from User PATH..." -ForegroundColor Yellow
$userPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
if ($userPath) {
    $parts    = $userPath -split ';' | Where-Object { $_ -ne '' }
    $cleaned  = $parts | Where-Object {
        $_ -notmatch [regex]::Escape($INSTALL_DIR) -and
        $_ -notmatch [regex]::Escape($BIN_DIR)
    }
    $newPath = $cleaned -join ';'
    if ($newPath -ne $userPath) {
        [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::User)
        Write-Host "  OK  Removed WTStudio entries from User PATH." -ForegroundColor Green
    } else {
        Write-Host "  No WTStudio entries found in User PATH."
    }
}

# 4. Optional: purge license data
Write-Host "[4/4] License data..." -ForegroundColor Yellow
if ($PurgeLicense) {
    try {
        $credTarget = "wtstudio_license"
        $removed = cmdkey /delete:$credTarget 2>&1
        Write-Host "  OK  License data purged." -ForegroundColor Green
    } catch {
        Write-Host "  WARN Could not purge license data: $_" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "  License data retained. Use -PurgeLicense to remove."
}

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Green
Write-Host "  WTStudio uninstallation complete." -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Open a NEW terminal to confirm 'wtstudio' no longer resolves:" -ForegroundColor DarkGray
Write-Host "  where.exe wtstudio" -ForegroundColor DarkGray
Write-Host ""