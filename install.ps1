# WTStudio One-Command Installer
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -Command "irm 'https://raw.githubusercontent.com/wtrg/wtstudio-distribution/main/install.ps1' | iex"

$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  WTStudio Automated Windows Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$InstallDir = "$env:LOCALAPPDATA\WTStudio"
$BinDir = "$InstallDir\bin"
$ZipUrl = "https://github.com/wtrg/wtstudio-distribution/releases/download/v4.05.1/pyVideoTrans-Windows.zip"
$ChecksumUrl = "https://github.com/wtrg/wtstudio-distribution/releases/download/v4.05.1/SHA256SUMS.txt"

# Create directories
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
New-Item -ItemType Directory -Path $BinDir -Force | Out-Null

$TempZip = "$env:TEMP\WTStudio-Portable-Windows.zip"
$TempChecksum = "$env:TEMP\SHA256SUMS.txt"

try {
    Write-Host "[1/5] Downloading WTStudio release package..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $ZipUrl -OutFile $TempZip -UseBasicParsing
    Invoke-WebRequest -Uri $ChecksumUrl -OutFile $TempChecksum -UseBasicParsing

    Write-Host "[2/5] Verifying SHA-256 checksum..." -ForegroundColor Yellow
    $ActualHash = (Get-FileHash -Path $TempZip -Algorithm SHA256).Hash.ToLower()
    $ExpectedLine = Get-Content $TempChecksum | Select-String -Pattern "WTStudio-Portable-Windows.zip"
    if ($ExpectedLine) {
        $ExpectedHash = $ExpectedLine.ToString().Split(' ')[0].ToLower()
        if ($ActualHash -ne $ExpectedHash) {
            throw "SHA-256 verification failed! Expected: $ExpectedHash, Got: $ActualHash"
        }
        Write-Host "  ✓ SHA-256 checksum verified ($ActualHash)" -ForegroundColor Green
    } else {
        Write-Host "  ! Warning: Checksum manifest empty, skipping SHA check" -ForegroundColor Yellow
    }

    Write-Host "[3/5] Extracting WTStudio files to $InstallDir..." -ForegroundColor Yellow
    Get-Process -Name "sp" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 300

    # Clean existing app files except user data
    if (Test-Path "$InstallDir\_internal") { Remove-Item "$InstallDir\_internal" -Recurse -Force }
    if (Test-Path "$InstallDir\sp.exe") { Remove-Item "$InstallDir\sp.exe" -Force }

    Expand-Archive -Path $TempZip -DestinationPath $InstallDir -Force

    Write-Host "[4/5] Creating launcher alias wtstudio.cmd..." -ForegroundColor Yellow
    $CmdContent = "@echo off`r`n`"%InstallDir%\sp.exe`" %*"
    Set-Content -Path "$BinDir\wtstudio.cmd" -Value $CmdContent -Encoding ASCII

    Write-Host "[5/5] Registering $BinDir in User PATH..." -ForegroundColor Yellow
    $UserPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
    if ($UserPath -notlike "*$BinDir*") {
        $NewPath = "$UserPath;$BinDir"
        [Environment]::SetEnvironmentVariable("PATH", $NewPath, [EnvironmentVariableTarget]::User)
        Write-Host "  ✓ Added $BinDir to User PATH." -ForegroundColor Green
    } else {
        Write-Host "  ✓ $BinDir is already in User PATH." -ForegroundColor Green
    }

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  WTStudio 4.05.1 Installation Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Open a NEW terminal window and run:" -ForegroundColor White
    Write-Host "  wtstudio" -ForegroundColor Cyan

} finally {
    if (Test-Path $TempZip) { Remove-Item $TempZip -Force -ErrorAction SilentlyContinue }
    if (Test-Path $TempChecksum) { Remove-Item $TempChecksum -Force -ErrorAction SilentlyContinue }
}
