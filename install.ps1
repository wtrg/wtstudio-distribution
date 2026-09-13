# WTStudio public installer.
# Downloads the latest release from wtrg/wtstudio-distribution.

param(
    [string]$InstallDir = "$env:LOCALAPPDATA\WTStudio",
    [switch]$EnableStartup
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$releaseApi = "https://api.github.com/repos/wtrg/wtstudio-distribution/releases/latest"
$tempZip = Join-Path $env:TEMP "WTStudio-edge-processor-$([guid]::NewGuid().ToString('N')).zip"

function Register-ProcessorProtocol {
    param([string]$ProcessorPath)

    $protocolKey = 'HKCU:\Software\Classes\wtstudio'
    $commandKey = Join-Path $protocolKey 'shell\open\command'
    New-Item -Path $commandKey -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -Path $protocolKey -Name '(Default)' -Value 'URL:WTStudio Processor' -PropertyType String -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -Path $protocolKey -Name 'URL Protocol' -Value '' -PropertyType String -Force -ErrorAction Stop | Out-Null
    $command = '"{0}" _serve --host 127.0.0.1 --port 8765 --no-browser' -f $ProcessorPath
    New-ItemProperty -Path $commandKey -Name '(Default)' -Value $command -PropertyType String -Force -ErrorAction Stop | Out-Null
}

function Get-Sha256Hex {
    param([string]$Path)
    $stream = $null
    $sha = $null
    try {
        $stream = [IO.File]::OpenRead($Path)
        $sha = [Security.Cryptography.SHA256]::Create()
        return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    } finally {
        if ($sha) { $sha.Dispose() }
        if ($stream) { $stream.Dispose() }
    }
}

Write-Host "WTStudio installer" -ForegroundColor Cyan
Write-Host "[1/5] Checking latest release..." -ForegroundColor Yellow
$release = Invoke-RestMethod -Uri $releaseApi -Headers @{
    "User-Agent" = "WTStudio-Installer"
    "Accept" = "application/vnd.github+json"
}
$releaseVersion = $release.tag_name.TrimStart('v')
$releaseAsset = $release.assets |
    Where-Object { $_.name -like "WTStudio-$releaseVersion-EdgeProcessor*.zip" -and $_.name -notlike '*Delta*' } |
    Select-Object -First 1
if (-not $releaseAsset) {
    throw "No Edge-TTS processor ZIP found in the latest distribution release."
}

Write-Host "[2/5] Downloading WTStudio $releaseVersion..." -ForegroundColor Yellow
Invoke-WebRequest -Uri $releaseAsset.browser_download_url -OutFile $tempZip -UseBasicParsing

if ($releaseAsset.size -and (Get-Item -LiteralPath $tempZip).Length -ne [int64]$releaseAsset.size) {
    throw "Downloaded file size does not match the GitHub release asset."
}
if ($releaseAsset.digest -and $releaseAsset.digest.StartsWith("sha256:")) {
    $expectedHash = $releaseAsset.digest.Substring(7).ToLowerInvariant()
    $actualHash = Get-Sha256Hex $tempZip
    if ($actualHash -ne $expectedHash) {
        throw "Downloaded file checksum does not match the GitHub release asset."
    }
}

Write-Host "[3/5] Preserving the existing installation and installing the Edge-TTS processor..." -ForegroundColor Yellow
$runningProcesses = @(Get-Process -Name "wtstudio", "vietdub-processor" -ErrorAction SilentlyContinue)
if ($runningProcesses.Count -gt 0) {
    Write-Host "Stopping running WTStudio processes..." -ForegroundColor Yellow
    $runningProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
$tempExtract = Join-Path $env:TEMP "WTStudio-extract-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null
Expand-Archive -LiteralPath $tempZip -DestinationPath $tempExtract -Force
$packageRoot = Join-Path $tempExtract "WTStudio"
if (-not (Test-Path -LiteralPath (Join-Path $packageRoot "vietdub-processor\vietdub-processor.exe"))) {
    $packageRoot = $tempExtract
}
foreach ($item in Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Force) {
    $relative = $item.FullName.Substring($packageRoot.TrimEnd('\').Length + 1)
    $dest = Join-Path $InstallDir $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
    Copy-Item -LiteralPath $item.FullName -Destination $dest -Force
}
foreach ($required in @('vietdub-processor\vietdub-processor.exe', 'ffmpeg\ffmpeg.exe', 'ffmpeg\ffprobe.exe')) {
    $sourceFile = Join-Path $packageRoot $required
    $targetFile = Join-Path $InstallDir $required
    if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf) -or
        -not (Test-Path -LiteralPath $targetFile -PathType Leaf) -or
        (Get-Sha256Hex $sourceFile) -ne (Get-Sha256Hex $targetFile)) {
        throw "Installation verification failed: $required does not match the release."
    }
}
Remove-Item -LiteralPath $tempExtract -Recurse -Force
Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path (Join-Path $InstallDir "runtime") -Force | Out-Null
Set-Content -LiteralPath (Join-Path $InstallDir "runtime\installed_release_version.txt") -Value $releaseVersion -Encoding UTF8
$processorExe = Join-Path $InstallDir "vietdub-processor\vietdub-processor.exe"
if (-not (Test-Path -LiteralPath $processorExe)) {
    throw "The Edge-TTS processor was not found after installation."
}
$ffmpegDir = Join-Path $InstallDir "ffmpeg"
foreach ($binaryName in @('ffmpeg.exe', 'ffprobe.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $ffmpegDir $binaryName) -PathType Leaf)) {
        throw "The WTStudio package is incomplete: $binaryName is missing from the bundled ffmpeg folder."
    }
}
Register-ProcessorProtocol -ProcessorPath $processorExe

Write-Host "[4/5] Creating launcher..." -ForegroundColor Yellow
$cmdContent = @"
@echo off
"%~dp0vietdub-processor\vietdub-processor.exe" %*
"@
$cmdContent | Out-File (Join-Path $InstallDir "vietdub-processor.cmd") -Encoding ASCII -Force

Write-Host "[5/5] Updating PATH and shortcut..." -ForegroundColor Yellow
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$InstallDir", "User")
}
# Keep the shell that executed `irm ... | iex` usable immediately.  Updating
# the User-scoped environment variable only affects processes created later;
# the current PowerShell process keeps its old PATH otherwise, so `wtstudio`
# fails until the user opens another terminal.
$currentPathEntries = @($env:Path -split ';' | Where-Object { $_ })
$installPath = $InstallDir.TrimEnd('\')
$pathAlreadyLoaded = $currentPathEntries | Where-Object {
    $_.TrimEnd('\') -ieq $installPath
}
if (-not $pathAlreadyLoaded) {
    $env:Path = "$InstallDir;$env:Path"
}
$desktop = [Environment]::GetFolderPath("Desktop")
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path $desktop "WT Studio.lnk"))
$desktopTarget = Join-Path $InstallDir "wtstudio.exe"
if (-not (Test-Path -LiteralPath $desktopTarget)) { $desktopTarget = $processorExe }
$shortcut.TargetPath = $processorExe
$shortcut.Arguments = "_serve --host 127.0.0.1 --port 8765 --no-browser"
$shortcut.WorkingDirectory = $InstallDir
$shortcut.Save()

if ($EnableStartup) {
    $startupDir = [Environment]::GetFolderPath("Startup")
    $startupShortcut = $shell.CreateShortcut((Join-Path $startupDir "WT Studio (background).lnk"))
    $startupShortcut.TargetPath = $processorExe
    $startupShortcut.Arguments = "_serve --host 127.0.0.1 --port 8765 --no-browser"
    $startupShortcut.WorkingDirectory = $InstallDir
    $startupShortcut.WindowStyle = 7
    $startupShortcut.Save()
    Write-Host "Background server startup enabled. Open the web app when needed." -ForegroundColor DarkCyan
} else {
    Write-Host "Background startup is off. Enable later with -EnableStartup." -ForegroundColor DarkGray
}

Write-Host "WTStudio Edge-TTS processor $releaseVersion installed successfully." -ForegroundColor Green
Write-Host "Processor URI registered for the current Windows user." -ForegroundColor DarkCyan
Write-Host "Run 'vietdub-processor' or open the web app to start the local processor." -ForegroundColor Cyan
