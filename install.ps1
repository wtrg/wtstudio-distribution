# WTStudio public installer.
# Downloads the latest release from wtrg/wtstudio-distribution.

param(
    [string]$InstallDir = "$env:LOCALAPPDATA\WTStudio",
    [string]$ReleaseTag = "",
    [switch]$EnableStartup
)

$ReleaseTag = $ReleaseTag.Trim()
if ($ReleaseTag -and -not $PSBoundParameters.ContainsKey('InstallDir')) {
    $InstallDir = Join-Path $env:LOCALAPPDATA 'WTStudio-Preview'
}

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$releaseApi = if ($ReleaseTag) {
    "https://api.github.com/repos/wtrg/wtstudio-distribution/releases/tags/$([uri]::EscapeDataString($ReleaseTag))"
} else {
    "https://api.github.com/repos/wtrg/wtstudio-distribution/releases/latest"
}
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
$releaseVersion = ($release.tag_name.TrimStart('v') -split '-')[0]
$useLocalUi = [version]$releaseVersion -ge [version]'2.0.64'
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

$quickLauncherContent = if ($useLocalUi) { @"
@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0wt-launch.ps1"
endlocal
"@ } else { @"
@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "`$healthy=`$false; try { `$null=Invoke-RestMethod -Uri 'http://127.0.0.1:8765/api/health' -TimeoutSec 2 -Headers @{ Origin='https://wtstudio-ai.pages.dev' }; `$healthy=`$true } catch {}; if (-not `$healthy) { Start-Process -WindowStyle Hidden -FilePath '%~dp0vietdub-processor\vietdub-processor.exe' -ArgumentList '_serve','--host','127.0.0.1','--port','8765','--no-browser' -WorkingDirectory '%~dp0vietdub-processor' }; Start-Process 'https://wtstudio-ai.pages.dev/'"
endlocal
"@ }
$quickLauncherContent | Out-File (Join-Path $InstallDir "wt.cmd") -Encoding ASCII -Force
if ($useLocalUi) {
    $localLauncher = @'
param([string]$Command, [string]$Arg1)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$processor = Join-Path $installDir 'vietdub-processor\vietdub-processor.exe'

# 1. Xu ly lenh wt update / wt --update
if ($Command -in @('update', '--update', '-u')) {
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "          WT STUDIO - DANG TIEN HANH CAP NHAT HE THONG                " -ForegroundColor Yellow
    Write-Host "======================================================================" -ForegroundColor Cyan
    powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/wtrg/wtstudio-distribution/main/install.ps1 | iex"
    exit 0
}

# 2. Xu ly lenh wt check-update / wt --check-update
if ($Command -in @('check-update', '--check-update', 'check')) {
    if (Test-Path $processor) {
        & $processor --check-update
    } else {
        $online = (Invoke-RestMethod -Uri "https://raw.githubusercontent.com/wtrg/wtstudio-distribution/main/version.json").version
        Write-Host "Phien ban online moi nhat: v$online"
    }
    exit 0
}

# 3. Xu ly lenh wt key
if ($Command -in @('key', '--key')) {
    if ($Arg1 -and (Test-Path $processor)) {
        & $processor --key $Arg1 --check-key
    } elseif (Test-Path $processor) {
        & $processor --check-key
    }
    exit 0
}

# Xac dinh phien ban hien tai
$current = "__RELEASE_VERSION__"
if (Test-Path (Join-Path $installDir "version.json")) {
    try { $current = (Get-Content (Join-Path $installDir "version.json") | ConvertFrom-Json).version } catch {}
}

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "   WT STUDIO - VIETDUB VIDEO AI (HE THONG LONG TIENG & RENDER)        " -ForegroundColor Yellow
Write-Host "   Phien ban may cua ban: v$current  |  Platform: Windows x64         " -ForegroundColor White
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host " [UPDATE] Dang kiem tra ban cap nhat tu GitHub..." -ForegroundColor Gray

# 4. Kiem tra cap nhat tu GitHub Distribution
try {
    $verData = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/wtrg/wtstudio-distribution/main/version.json" -TimeoutSec 4 -Headers @{ "User-Agent" = "WTStudio" }
    $latest = $verData.version
    if ($latest -and [version]$latest -gt [version]$current) {
        Write-Host "----------------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host " [UPDATE] >>> DA CO BAN CAP NHAT MOI: v$latest (Hien tai: v$current) <<<" -ForegroundColor Red
        Write-Host " Tinh nang noi bat:" -ForegroundColor White
        foreach ($f in $verData.features) { Write-Host "   + $f" -ForegroundColor Yellow }
        Write-Host "----------------------------------------------------------------------" -ForegroundColor Yellow
        $ans = Read-Host " >> Ban co muon cap nhat ngay bay gio? (Y/N) [Y]"
        if ($ans -eq "" -or $ans -match "^[Yy]") {
            Write-Host " [UPDATE] Dang tai va cai dat ban moi v$latest..." -ForegroundColor Green
            powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/wtrg/wtstudio-distribution/main/install.ps1 | iex"
            exit 0
        }
    } else {
        Write-Host " [UPDATE] [OK] Ban dang su dung phien ban moi nhat (v$current)." -ForegroundColor Green
    }
} catch {
    Write-Host " [UPDATE] Khong the ket noi GitHub kiem tra update ($($_.Exception.Message))." -ForegroundColor DarkGray
}
Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray

# 5. Khoi dong Processor neu chua chay
Write-Host " [PROCESSOR] Dang kiem tra bo xu ly local tren cong 8765..." -ForegroundColor Gray
$healthy = $false
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    try {
        $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/api/health' -TimeoutSec 2
        if ($health.status -eq 'ok') { $healthy = $true; break }
    } catch { }
    if ($attempt -eq 0 -and (Test-Path $processor)) {
        Write-Host " [PROCESSOR] Dang khoi dong vietdub-processor chay nen..." -ForegroundColor Gray
        Start-Process -WindowStyle Hidden -FilePath $processor -ArgumentList @('_serve','--host','127.0.0.1','--port','8765','--no-browser') -WorkingDirectory (Split-Path -Parent $processor)
    }
    Start-Sleep -Milliseconds 500
}
if (-not $healthy) { 
    Write-Host " [!] LOI: VietDub local khong khoi dong duoc. Kiem tra cong 8765." -ForegroundColor Red
    throw 'VietDub local khong khoi dong duoc.'
}

Write-Host " [PROCESSOR] [OK] Bo xu ly local da san sang (Port 8765)!" -ForegroundColor Green
Write-Host " [WEB] Dang mo giao dien WT Studio tren trinh duyet: https://wtstudio-ai.pages.dev/" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Start-Process 'https://wtstudio-ai.pages.dev/'
'@
    $localLauncher.Replace('__RELEASE_VERSION__', $releaseVersion) | Set-Content -LiteralPath (Join-Path $InstallDir 'wt-launch.ps1') -Encoding UTF8
}

Write-Host "[5/5] Updating PATH and shortcut..." -ForegroundColor Yellow
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$normalizedInstallDir = $InstallDir.TrimEnd('\')
$userPathEntries = @($userPath -split ';' | Where-Object {
    $_ -and $_.TrimEnd('\') -ine $normalizedInstallDir
})
# Keep WTStudio first because WindowsApps may already provide wt.exe.
[Environment]::SetEnvironmentVariable("Path", ((@($InstallDir) + $userPathEntries) -join ';'), "User")
# Keep the shell that executed `irm ... | iex` usable immediately.  Updating
# the User-scoped environment variable only affects processes created later;
# the current PowerShell process keeps its old PATH otherwise, so `wtstudio`
# fails until the user opens another terminal.
$currentPathEntries = @($env:Path -split ';' | Where-Object { $_ })
$installPath = $normalizedInstallDir
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
$shortcut.TargetPath = if ($useLocalUi) { Join-Path $InstallDir 'wt.cmd' } else { $processorExe }
$shortcut.Arguments = if ($useLocalUi) { '' } else { '_serve --host 127.0.0.1 --port 8765 --no-browser' }
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

Write-Host "Starting processor and verifying the local connection..." -ForegroundColor Yellow
$processorLog = Join-Path $InstallDir 'runtime\processor-start.stdout.log'
$processorErrorLog = Join-Path $InstallDir 'runtime\processor-start.stderr.log'
Start-Process -WindowStyle Hidden -FilePath $processorExe `
    -ArgumentList @('_serve', '--host', '127.0.0.1', '--port', '8765', '--no-browser') `
    -WorkingDirectory (Split-Path -Parent $processorExe) `
    -RedirectStandardOutput $processorLog -RedirectStandardError $processorErrorLog -ErrorAction Stop | Out-Null
$verifiedHealth = $null
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    try {
        $candidate = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/api/health' -TimeoutSec 2 -Headers @{ Origin = 'https://wtstudio-ai.pages.dev' }
        if ($candidate.version -eq $releaseVersion -and $candidate.capabilities.ffmpeg -and $candidate.capabilities.ffprobe -and $candidate.capabilities.edge_tts) {
            $verifiedHealth = $candidate
            break
        }
    } catch { }
    Start-Sleep -Milliseconds 500
}
if (-not $verifiedHealth) {
    throw "Files installed, but processor startup verification failed. Check $processorErrorLog. Do not reinstall repeatedly; send this log to support."
}
Write-Host "WTStudio Edge-TTS processor $releaseVersion installed, running and verified on port 8765." -ForegroundColor Green
Write-Host "Quick launch command installed: wt" -ForegroundColor Green
if ($useLocalUi) { Write-Host "wt opens VietDub at http://127.0.0.1:8765/" -ForegroundColor Green }
Write-Host "Processor URI registered for the current Windows user." -ForegroundColor DarkCyan
Write-Host "Next time, open PowerShell or CMD and run: wt" -ForegroundColor Cyan
