#Requires -Version 5.1
# WTStudio Uninstaller
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1
#
# Safe to run multiple times (idempotent).
# Does NOT delete user project files or video output.
# Does NOT delete license activation data unless --purge-license is passed.

param(
    [switch]$PurgeLicense = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'  # Don't stop on individual cleanup errors

$INSTALL_DIR = "$env:LOCALAPPDATA\WTStudio"
$BIN_DIR     = "$INSTALL_DIR\bin"

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  WTStudio Uninstaller" -ForegroundColor Cyan
Write-Host "  Install dir : $INSTALL_DIR" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

# â”€â”€ 1. Stop running sp.exe processes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

# â”€â”€ 2. Remove installation bundle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "[2/4] Removing WTStudio installation files..." -ForegroundColor Yellow
if (Test-Path -LiteralPath $INSTALL_DIR) {
    # Reset any read-only attributes that might block deletion
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
    Write-Host "  $INSTALL_DIR does not exist â€” nothing to remove."
}

# â”€â”€ 3. Clean User PATH â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "[3/4] Removing $BIN_DIR from User PATH..." -ForegroundColor Yellow
$userPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
if ($userPath) {
    $parts    = $userPath -split ';' | Where-Object { $_ -ne '' }
    $cleaned  = $parts | Where-Object {
        # Remove any path that is or is under $INSTALL_DIR
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

# â”€â”€ 4. Optional: purge license data â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "[4/4] License data..." -ForegroundColor Yellow
if ($PurgeLicense) {
    # License is stored in the Windows Credential Manager / keyring
    # Remove keyring entries for WTStudio
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
