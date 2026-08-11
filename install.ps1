# WTStudio public installer.
# Downloads the latest release from tranvantruonguser-cmd/wtrg-dis-2.

param(
    [string]$InstallDir = "$env:LOCALAPPDATA\WTStudio"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$releaseApi = "https://api.github.com/repos/tranvantruonguser-cmd/wtrg-dis-2/releases/latest"
$workspaceRoot = $env:PYVIDEOTRANS_UPDATE_TEMP
if (-not $workspaceRoot) {
    $workspaceRoot = Get-PSDrive -PSProvider FileSystem |
        Where-Object { $_.Free -gt 0 -and $_.Root } |
        Sort-Object Free -Descending |
        Select-Object -First 1 -ExpandProperty Root
}
if (-not $workspaceRoot) {
    $workspaceRoot = $env:TEMP
}
$workspace = Join-Path $workspaceRoot "WTStudio-install-$([guid]::NewGuid().ToString('N'))"
$tempZip = Join-Path $workspace "WTStudio-latest.zip"
$tempExtract = Join-Path $workspace "extract"
New-Item -ItemType Directory -Path $workspace -Force | Out-Null

trap {
    if (Test-Path -LiteralPath $workspace) {
        Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
    }
    throw
}

Write-Host "WTStudio installer" -ForegroundColor Cyan
Write-Host "[1/5] Checking latest release..." -ForegroundColor Yellow
$release = Invoke-RestMethod -Uri $releaseApi -Headers @{
    "User-Agent" = "WTStudio-Installer"
    "Accept" = "application/vnd.github+json"
}
$releaseVersion = $release.tag_name.TrimStart('v')
$releaseAsset = $release.assets |
    Where-Object { $_.name -like "WTStudio-$releaseVersion*.zip" } |
    Select-Object -First 1
if (-not $releaseAsset) {
    $releaseAsset = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
}
if (-not $releaseAsset) {
    throw "No ZIP asset found in the latest distribution release."
}

Write-Host "[2/5] Downloading WTStudio $releaseVersion..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $releaseAsset.browser_download_url -OutFile $tempZip -UseBasicParsing

Write-Host "[3/5] Preserving user data and installing..." -ForegroundColor Yellow
$preservePaths = @("logs", "tmp", "models", "runtime", "videotrans\cfg.json", "videotrans\params.json")
$runningProcesses = @(Get-Process -Name "wtstudio" -ErrorAction SilentlyContinue)
if ($runningProcesses.Count -gt 0) {
    Write-Host "Stopping running WTStudio processes..." -ForegroundColor Yellow
    $runningProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null
Expand-Archive -LiteralPath $tempZip -DestinationPath $tempExtract -Force
$packageRoot = Join-Path $tempExtract "WTStudio"
if (-not (Test-Path -LiteralPath (Join-Path $packageRoot "wtstudio.exe"))) {
    $packageRoot = $tempExtract
}
Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Force | ForEach-Object {
    $relativePath = $_.FullName.Substring($packageRoot.Length + 1)
    $shouldPreserve = $false
    foreach ($preservePath in $preservePaths) {
        if ($relativePath -eq $preservePath -or $relativePath.StartsWith(
            "$preservePath\", [System.StringComparison]::OrdinalIgnoreCase
        )) {
            $shouldPreserve = $true
            break
        }
    }
    if (-not $shouldPreserve) {
        $destination = Join-Path $InstallDir $relativePath
        $destinationDir = Split-Path $destination -Parent
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
    }
}
New-Item -ItemType Directory -Path (Join-Path $InstallDir "runtime") -Force | Out-Null
Set-Content -LiteralPath (Join-Path $InstallDir "runtime\installed_release_version.txt") -Value $releaseVersion -Encoding UTF8
Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "[4/5] Creating launcher..." -ForegroundColor Yellow
$cmdContent = @"
@echo off
"%~dp0wtstudio.exe" %*
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
