# WT Studio - Ultimate One-Liner Installer
# Không cần tải script, mọi thứ trong 1 lệnh

param(
    [string]$InstallDir = "$env:LOCALAPPDATA\WTStudio"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  WT Studio Smart Installer                                ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Download
Write-Host "[1/5] Tải WT Studio..." -ForegroundColor Yellow
$tempZip = "$env:TEMP\WTStudio.zip"
$url = "https://github.com/wtrg/wtstudio-distribution/releases/download/v2026.08.07/WTStudio-2026.08.07.zip"

try {
    Invoke-WebRequest -Uri $url -OutFile $tempZip -UseBasicParsing
    $sizeMB = [math]::Round((Get-Item $tempZip).Length / 1MB, 2)
    Write-Host "  ✓ Đã tải ($sizeMB MB)" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Lỗi: $_" -ForegroundColor Red
    exit 1
}

# Extract
Write-Host "`n[2/5] Giải nén..." -ForegroundColor Yellow
if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Expand-Archive -Path $tempZip -DestinationPath $InstallDir -Force
Remove-Item $tempZip -Force
Write-Host "  ✓ Đã giải nén" -ForegroundColor Green

# Create launcher
Write-Host "`n[3/5] Tạo launcher..." -ForegroundColor Yellow
@"
@echo off
start "" "%~dp0wtstudio.exe"
timeout /t 2 /nobreak >nul
start http://localhost:8765
exit
"@ | Out-File "$InstallDir\wtstudio.cmd" -Encoding ASCII
Write-Host "  ✓ Đã tạo" -ForegroundColor Green

# Add to PATH
Write-Host "`n[4/5] Thêm vào PATH..." -ForegroundColor Yellow
$path = [Environment]::GetEnvironmentVariable("Path", "User")
if ($path -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$path;$InstallDir", "User")
    Write-Host "  ✓ Đã thêm" -ForegroundColor Green
} else {
    Write-Host "  ✓ Đã có" -ForegroundColor Green
}

# Shortcuts
Write-Host "`n[5/5] Tạo shortcut..." -ForegroundColor Yellow
$desktop = [Environment]::GetFolderPath("Desktop")
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut("$desktop\WT Studio.lnk")
$shortcut.TargetPath = "$InstallDir\wtstudio.exe"
$shortcut.WorkingDirectory = $InstallDir
$shortcut.Save()
Write-Host "  ✓ Desktop shortcut" -ForegroundColor Green

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  ✅ HOÀN TẤT!                                             ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Lần sau chỉ cần gõ: wtstudio" -ForegroundColor Green
Write-Host ""

if ((Read-Host "Chạy ngay? (Y/n)") -ne 'n') {
    Start-Process "$InstallDir\wtstudio.exe"
    Start-Sleep -Seconds 2
    Start-Process "http://localhost:8765"
}
