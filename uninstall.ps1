# WTStudio Uninstaller Script
$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  WTStudio Uninstaller" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$InstallDir = "$env:LOCALAPPDATA\WTStudio"
$BinDir = "$InstallDir\bin"

# 1. Stop running processes
Get-Process -Name "sp" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

# 2. Remove Installation Directory
if (Test-Path -LiteralPath $InstallDir) {
    Get-ChildItem -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Attributes = 'Normal' }
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Host "✓ Removed $InstallDir" -ForegroundColor Green
}

# 3. Clean User PATH
$UserPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
if ($UserPath -like "*$BinDir*") {
    $NewPath = ($UserPath -split ';' | Where-Object { $_ -ne $BinDir -and $_ -ne "$InstallDir\bin" }) -join ';'
    [Environment]::SetEnvironmentVariable("PATH", $NewPath, [EnvironmentVariableTarget]::User)
    Write-Host "✓ Removed $BinDir from User PATH." -ForegroundColor Green
}

Write-Host "WTStudio uninstallation completed successfully." -ForegroundColor Green
