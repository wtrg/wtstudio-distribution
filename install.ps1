# WTStudio public installer.
# Downloads the latest release from wtrg/wtstudio-distribution.

param(
    [string]$InstallDir = "$env:LOCALAPPDATA\WTStudio"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$releaseApi = "https://api.github.com/repos/wtrg/wtstudio-distribution/releases/latest"
$tempZip = Join-Path $env:TEMP "WTStudio-latest.zip"
$backupDir = Join-Path $env:TEMP "WTStudio-install-backup-$([guid]::NewGuid().ToString('N'))"

Write-Host "WTStudio installer" -ForegroundColor Cyan
Write-Host "[1/5] Checking latest release..." -ForegroundColor Yellow
$release = Invoke-RestMethod -Uri $releaseApi -Headers @{
    "User-Agent" = "WTStudio-Installer"
    "Accept" = "application/vnd.github+json"
}
$releaseAsset = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
if (-not $releaseAsset) {
    throw "No ZIP asset found in the latest distribution release."
}
$releaseVersion = $release.tag_name.TrimStart('v')

Write-Host "[2/5] Downloading WTStudio $releaseVersion..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $releaseAsset.browser_download_url -OutFile $tempZip -UseBasicParsing

Write-Host "[3/5] Preserving user data and installing..." -ForegroundColor Yellow
$preservePaths = @("logs", "tmp", "models", "runtime", "videotrans\cfg.json", "videotrans\params.json")
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
foreach ($relativePath in $preservePaths) {
    $sourcePath = Join-Path $InstallDir $relativePath
    if (Test-Path -LiteralPath $sourcePath) {
        $backupPath = Join-Path $backupDir $relativePath
        New-Item -ItemType Directory -Path (Split-Path $backupPath -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $backupPath -Recurse -Force
    }
}
if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Expand-Archive -LiteralPath $tempZip -DestinationPath $InstallDir -Force
Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue

foreach ($relativePath in $preservePaths) {
    $backupPath = Join-Path $backupDir $relativePath
    if (Test-Path -LiteralPath $backupPath) {
        $targetPath = Join-Path $InstallDir $relativePath
        New-Item -ItemType Directory -Path (Split-Path $targetPath -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $backupPath -Destination $targetPath -Recurse -Force
    }
}
Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path (Join-Path $InstallDir "runtime") -Force | Out-Null
Set-Content -LiteralPath (Join-Path $InstallDir "runtime\installed_release_version.txt") -Value $releaseVersion -Encoding UTF8

Write-Host "[4/5] Creating launcher..." -ForegroundColor Yellow
$cmdContent = @"
@echo off
start "" "%~dp0wtstudio.exe"
timeout /t 2 /nobreak >nul
start http://localhost:8765
exit
"@
$cmdContent | Out-File (Join-Path $InstallDir "wtstudio.cmd") -Encoding ASCII -Force

Write-Host "[5/5] Updating PATH and shortcut..." -ForegroundColor Yellow
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$InstallDir", "User")
}
$desktop = [Environment]::GetFolderPath("Desktop")
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path $desktop "WT Studio.lnk"))
$shortcut.TargetPath = Join-Path $InstallDir "wtstudio.exe"
$shortcut.WorkingDirectory = $InstallDir
$shortcut.Save()

Write-Host "WTStudio $releaseVersion installed successfully." -ForegroundColor Green
Write-Host "Run 'wtstudio' again to start the tool." -ForegroundColor Cyan
