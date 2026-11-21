if (-not $PSCommandPath) { $__f = Join-Path $env:TEMP "wtstudio-install-$([guid]::NewGuid().ToString('N')).ps1"; try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13; $wc = New-Object System.Net.WebClient; $wc.Headers.Add('User-Agent', 'WTStudio-Installer/2.0.85'); $wc.DownloadFile('https://wtstudio-gateway.wtshop.workers.dev/install.ps1', $__f); & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $__f; exit $LASTEXITCODE } finally { Remove-Item -LiteralPath $__f -Force -ErrorAction SilentlyContinue } }
# ==============================================================================
# WT STUDIO - COMMERCIAL ONE-LINE WINDOWS INSTALLER
# Usage (Mode 2A - Auto activate):
#   $env:WT_KEY="WTS-XXXX-XXXX-XXXX-XXXX"; irm https://wtstudio-gateway.wtshop.workers.dev/install.ps1 | iex
# Usage (Mode 2B - Activate on Web UI):
#   irm https://wtstudio-gateway.wtshop.workers.dev/install.ps1 | iex
# ==============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13

$GatewayBase = if ($env:WT_GATEWAY_URL) { $env:WT_GATEWAY_URL.TrimEnd('/') } else { 'https://wtstudio-gateway.wtshop.workers.dev' }
$InstallDir  = if ($env:WT_INSTALL_DIR) { $env:WT_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'WTStudio' }
$DataRoot    = if ($env:WT_DATA_ROOT) { $env:WT_DATA_ROOT } else { Join-Path $env:LOCALAPPDATA 'VietDubVideo' }
$Port        = if ($env:WT_PORT -and $env:WT_PORT -match '^\d+$') { [int]$env:WT_PORT } else { 8765 }
$ArchivePath = if ($env:WT_ARCHIVE_PATH) { $env:WT_ARCHIVE_PATH.Trim() } else { '' }
$NoBrowser   = ($env:WT_NO_BROWSER -eq '1')
$SkipShortcut = ($env:WT_SKIP_SHORTCUT -eq '1')
$SkipPath    = ($env:WT_SKIP_PATH -eq '1')

$LicenseKey = if ($env:WT_KEY) { $env:WT_KEY.Trim() } else { '' }
if ($LicenseKey -match '^(?i)wts-') { $LicenseKey = $LicenseKey.ToUpperInvariant() }
if ($LicenseKey -and $LicenseKey -notmatch '^(WTS-[A-Z0-9]{4}(-[A-Z0-9]{4}){2,3}|wtd_[a-f0-9]{64})$') {
    Write-Host " [!] Canh bao: Ma ban quyen '$LicenseKey' khong dung dinh dang chuan (WTS-XXXX-XXXX-XXXX-XXXX)." -ForegroundColor Red
    throw 'Ma ban quyen khong hop le. Vui long kiem tra lai tin nhan ban giao tu nguoi ban.'
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

function Register-ProcessorProtocol {
    param([string]$ProcessorPath, [int]$ListenPort)
    try {
        $protocolKey = 'HKCU:\Software\Classes\wtstudio'
        $commandKey = Join-Path $protocolKey 'shell\open\command'
        New-Item -Path $commandKey -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $protocolKey -Name '(Default)' -Value 'URL:WTStudio Processor' -PropertyType String -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $protocolKey -Name 'URL Protocol' -Value '' -PropertyType String -Force -ErrorAction Stop | Out-Null
        $command = '"{0}" _serve --host 127.0.0.1 --port {1} --no-browser --no-interactive' -f $ProcessorPath, $ListenPort
        New-ItemProperty -Path $commandKey -Name '(Default)' -Value $command -PropertyType String -Force -ErrorAction Stop | Out-Null
    } catch { }
}

function Stop-WTStudioPort {
    param([int]$ListenPort)
    Get-Process -Name 'vietdub-processor', 'wtstudio' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    try {
        $busy = Get-NetTCPConnection -LocalPort $ListenPort -State Listen -ErrorAction SilentlyContinue
        foreach ($conn in $busy) {
            if ($conn.OwningProcess -gt 0) {
                Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
            }
        }
    } catch { }
    Start-Sleep -Milliseconds 600
}

Write-Host ''
Write-Host '======================================================================' -ForegroundColor Cyan
Write-Host '         WT STUDIO - CAI DAT BAN THUONG MAI CHINH THUC                ' -ForegroundColor Yellow
Write-Host '======================================================================' -ForegroundColor Cyan

# [1/5] Fetch release manifest
Write-Host '[1/5] Dang kiem tra phien ban moi nhat...' -ForegroundColor Yellow
$manifest = $null
try {
    $manifest = Invoke-RestMethod -Uri "$GatewayBase/release.json" -TimeoutSec 12 -Headers @{ 'User-Agent' = 'WTStudio-Installer' }
} catch {
    Write-Host '  Khong tai duoc tu gateway, thu lay tu GitHub Releases...' -ForegroundColor DarkGray
    $ghRel = Invoke-RestMethod -Uri 'https://api.github.com/repos/wtrg/wtstudio-distribution/releases/latest' -TimeoutSec 12 -Headers @{ 'User-Agent' = 'WTStudio-Installer'; 'Accept' = 'application/vnd.github+json' }
    $ver = ($ghRel.tag_name.TrimStart('v') -split '-')[0]
    $asset = $ghRel.assets | Where-Object { $_.name -like "WTStudio-$ver-Commercial*.zip" } | Select-Object -First 1
    if (-not $asset) { throw 'Khong tim thay goi cai dat thuong mai tren GitHub Releases.' }
    $expected = ''
    if ($asset.digest -and $asset.digest.StartsWith('sha256:')) { $expected = $asset.digest.Substring(7).ToLowerInvariant() }
    $manifest = [PSCustomObject]@{
        version = $ver
        url     = $asset.browser_download_url
        sha256  = $expected
    }
}

$releaseVersion = "$($manifest.version)".Trim()
if ($releaseVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "Phien ban phat hanh khong hop le: $releaseVersion"
}
Write-Host "  -> Phien ban: v$releaseVersion" -ForegroundColor Green

$tempRoot = Join-Path $env:TEMP ("WTStudio-setup-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    # [2/5] Download & verify SHA-256
    if ($ArchivePath) {
        $zipPath = (Resolve-Path -LiteralPath $ArchivePath).Path
        Write-Host "[2/5] Su dung goi cai dat cuc bo: $zipPath" -ForegroundColor Yellow
    } else {
        $downloadUrl = [uri]$manifest.url
        if ($downloadUrl.Scheme -ne 'https' -or $downloadUrl.Host -ne 'github.com' -or -not $downloadUrl.AbsolutePath.StartsWith('/wtrg/wtstudio-distribution/releases/download/')) {
            throw "Dia chi tai xuong khong hop le: $($manifest.url)"
        }
        $zipPath = Join-Path $tempRoot "WTStudio-$releaseVersion-Commercial.zip"
        Write-Host "[2/5] Dang tai WT Studio v$releaseVersion (~620 MB, vui long cho 1-2 phut)..." -ForegroundColor Yellow
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            & curl.exe -fL --retry 3 --retry-delay 2 --progress-bar -o $zipPath $downloadUrl.AbsoluteUri
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $zipPath)) {
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add('User-Agent', 'WTStudio-Installer')
                $wc.DownloadFile($downloadUrl.AbsoluteUri, $zipPath)
            }
        } else {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add('User-Agent', 'WTStudio-Installer')
            $wc.DownloadFile($downloadUrl.AbsoluteUri, $zipPath)
        }
        Unblock-File -LiteralPath $zipPath -ErrorAction SilentlyContinue
    }

    if ($manifest.sha256 -and $manifest.sha256 -match '^[a-fA-F0-9]{64}$') {
        Write-Host '  -> Dang kiem tra toan ven SHA-256...' -ForegroundColor Gray
        $actualHash = Get-Sha256Hex $zipPath
        if ($actualHash -ne $manifest.sha256.ToLowerInvariant()) {
            throw "Loi kiem tra SHA-256! File tai ve bi hong. Vui long chay lai lenh cai dat."
        }
        Write-Host '  -> SHA-256 hop le.' -ForegroundColor Green
    }

    # Validate archive entries against zip-slip before extraction
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName -match '(^|[/\\])\.\.([/\\]|$)|^[\\/]|:') {
                throw 'Goi cai dat chua duong dan khong an toan.'
            }
            if (-not $entry.FullName.Replace('\', '/').StartsWith('WTStudio/')) {
                throw 'Cau truc goi cai dat khong dung chuan WTStudio.'
            }
        }
    } finally {
        $archive.Dispose()
    }

    # [3/5] Extract & cleanly install/upgrade
    Write-Host '[3/5] Dang giai nen va cai dat (giu nguyen du an & ban quyen cu)...' -ForegroundColor Yellow
    $extractDir = Join-Path $tempRoot 'extract'
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
    [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractDir)

    $bundleDir = Join-Path $extractDir 'WTStudio'
    if (-not (Test-Path -LiteralPath (Join-Path $bundleDir 'vietdub-processor\vietdub-processor.exe'))) {
        throw 'Thieu file loi vietdub-processor.exe trong goi cai dat.'
    }

    Stop-WTStudioPort -ListenPort $Port
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    # Cleanly replace processor, ffmpeg, models, licenses so zero legacy v2.0.83 files remain
    foreach ($sub in @('vietdub-processor', 'ffmpeg', 'models', 'licenses')) {
        $srcSub = Join-Path $bundleDir $sub
        $dstSub = Join-Path $InstallDir $sub
        if (Test-Path -LiteralPath $srcSub) {
            if (Test-Path -LiteralPath $dstSub) {
                Remove-Item -LiteralPath $dstSub -Recurse -Force -ErrorAction Stop
            }
            try {
                Move-Item -LiteralPath $srcSub -Destination $dstSub -Force
            } catch {
                Copy-Item -LiteralPath $srcSub -Destination $dstSub -Recurse -Force
            }
        }
    }
    foreach ($file in Get-ChildItem -LiteralPath $bundleDir -File -Force) {
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $InstallDir $file.Name) -Force
    }
    # Remove any obsolete legacy .env from install directory
    foreach ($oldEnv in @((Join-Path $InstallDir '.env'), (Join-Path $InstallDir 'vietdub-processor\.env'))) {
        if (Test-Path -LiteralPath $oldEnv) { Remove-Item -LiteralPath $oldEnv -Force -ErrorAction SilentlyContinue }
    }

    $processorExe = Join-Path $InstallDir 'vietdub-processor\vietdub-processor.exe'
    foreach ($req in @('vietdub-processor\vietdub-processor.exe', 'ffmpeg\ffmpeg.exe', 'ffmpeg\ffprobe.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $InstallDir $req) -PathType Leaf)) {
            throw "Cai dat that bai: thieu thanh phan bat buoc ($req)."
        }
    }

    Write-Host '  -> Dang go chan (Unblock-File) cho Windows...' -ForegroundColor Gray
    Get-ChildItem -LiteralPath $InstallDir -Recurse -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
    try { Add-MpPreference -ExclusionPath $InstallDir -ErrorAction SilentlyContinue } catch { }

    New-Item -ItemType Directory -Path (Join-Path $InstallDir 'runtime') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $InstallDir 'runtime\installed_release_version.txt') -Value $releaseVersion -Encoding UTF8
    Register-ProcessorProtocol -ProcessorPath $processorExe -ListenPort $Port

    # [4/5] Create launchers, PATH & Desktop shortcut
    Write-Host '[4/5] Dang tao trinh khoi dong nhanh (wtstudio / wt) va bieu tuong Desktop...' -ForegroundColor Yellow

    $launcherPs1 = @'
param([string]$Command, [string]$Arg1)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$processor = Join-Path $installDir 'vietdub-processor\vietdub-processor.exe'
$gateway = '__GATEWAY_BASE__'
$port = __PORT__
$dataRoot = '__DATA_ROOT__'
$env:VIETDUB_LICENSE_API_URL = $gateway
$env:VIETDUB_DATA_ROOT = $dataRoot
$env:VIETDUB_DEV_MODE = '0'
$env:VIETDUB_ALLOWED_ORIGINS = "http://127.0.0.1:$port,http://localhost:$port"

if ($Command -in @('update', '--update', '-u')) {
    Write-Host '=== WT STUDIO - DANG CAP NHAT PHIEN BAN MOI ===' -ForegroundColor Cyan
    $tmp = Join-Path $env:TEMP "wtstudio-update-$([guid]::NewGuid().ToString('N')).ps1"
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
        (New-Object System.Net.WebClient).DownloadFile("$gateway/install.ps1", $tmp)
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    exit 0
}

if ($Command -in @('stop', '--stop')) {
    Get-Process -Name 'vietdub-processor' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host '[OK] Da dung WT Studio.' -ForegroundColor Green
    exit 0
}

if ($Command -in @('check-update', '--check-update', 'check')) {
    $current = '__RELEASE_VERSION__'
    if (Test-Path (Join-Path $installDir 'runtime\installed_release_version.txt')) {
        try { $current = (Get-Content (Join-Path $installDir 'runtime\installed_release_version.txt')).Trim() } catch {}
    }
    try {
        $rel = Invoke-RestMethod -Uri "$gateway/release.json" -TimeoutSec 6 -Headers @{ 'User-Agent' = 'WTStudio' }
        Write-Host "Phien ban hien tai: v$current | Phien ban moi nhat: v$($rel.version)" -ForegroundColor Cyan
        if ([version]$rel.version -gt [version]$current) {
            Write-Host 'Da co ban cap nhat moi! Chay lenh: wtstudio update' -ForegroundColor Yellow
        } else {
            Write-Host '[OK] Ban dang dung phien ban moi nhat.' -ForegroundColor Green
        }
    } catch { Write-Host "Khong kiem tra duoc cap nhat: $($_.Exception.Message)" -ForegroundColor Red }
    exit 0
}

if ($Command -in @('key', '--key')) {
    if ($Arg1) {
        $normKey = $Arg1.Trim()
        if ($normKey -match '^(?i)wts-') { $normKey = $normKey.ToUpperInvariant() }
        try {
            $body = @{ key = $normKey } | ConvertTo-Json
            $res = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/license/activate" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 10
            if ($res.valid) { Write-Host '[OK] Kich hoat ban quyen thanh cong!' -ForegroundColor Green; exit 0 }
        } catch {
            Write-Host "[!] Chua kich hoat duoc qua server local ($($_.Exception.Message)). Hay mo tool va nhap key tren Web." -ForegroundColor Yellow
        }
    } else {
        try {
            $st = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/license/status" -TimeoutSec 5
            Write-Host ("Trang thai ban quyen: valid={0} | status={1}" -f $st.valid, $st.status) -ForegroundColor Cyan
        } catch { Write-Host 'WT Studio chua chay. Go wtstudio de mo.' -ForegroundColor Yellow }
    }
    exit 0
}

$current = '__RELEASE_VERSION__'
if (Test-Path (Join-Path $installDir 'runtime\installed_release_version.txt')) {
    try { $current = (Get-Content (Join-Path $installDir 'runtime\installed_release_version.txt')).Trim() } catch {}
}

Write-Host '======================================================================' -ForegroundColor Cyan
Write-Host "   WT STUDIO - VIETDUB VIDEO AI (v$current)                           " -ForegroundColor Yellow
Write-Host '======================================================================' -ForegroundColor Cyan

try {
    $rel = Invoke-RestMethod -Uri "$gateway/release.json" -TimeoutSec 3 -Headers @{ 'User-Agent' = 'WTStudio' }
    if ($rel.version -and [version]$rel.version -gt [version]$current) {
        Write-Host " [UPDATE] Da co ban moi v$($rel.version)! Go 'wtstudio update' de nang cap." -ForegroundColor Yellow
    }
} catch { }

$healthy = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/health" -TimeoutSec 2
        if ($health.status -eq 'ok') { $healthy = $true; break }
    } catch { }
    if ($attempt -eq 0 -and (Test-Path $processor)) {
        try {
            $busyConns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
            foreach ($conn in $busyConns) {
                if ($conn.OwningProcess -gt 0) {
                    Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 300
                }
            }
        } catch { }
        Get-ChildItem -LiteralPath (Split-Path -Parent $processor) -Recurse -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
        try {
            Start-Process -WindowStyle Hidden -FilePath $processor -ArgumentList @('_serve', '--host', '127.0.0.1', '--port', "$port", '--no-browser', '--no-interactive') -WorkingDirectory (Split-Path -Parent $processor) -ErrorAction Stop
        } catch {
            if ($_.Exception.Message -match 'Application Control|blocked') {
                Write-Host '======================================================================' -ForegroundColor Red
                Write-Host ' [!] Windows 11 Smart App Control dang chan chay ung dung!' -ForegroundColor Yellow
                Write-Host ' Cach mo khoa (2 buoc):' -ForegroundColor White
                Write-Host " 1. Mo Start Menu -> tim 'Smart App Control' -> chuyen sang Off (Tat)" -ForegroundColor Cyan
                Write-Host " 2. Chay lai lenh: wtstudio" -ForegroundColor Green
                Write-Host '======================================================================' -ForegroundColor Red
                exit 1
            }
            throw
        }
    }
    Start-Sleep -Milliseconds 500
}
if (-not $healthy) {
    Write-Host " [!] Khong khoi dong duoc WT Studio tren cong $port." -ForegroundColor Red
    exit 1
}

Write-Host " [OK] WT Studio da san sang tai http://127.0.0.1:$port/" -ForegroundColor Green
Start-Process "http://127.0.0.1:$port/"
'@
    $launcherPs1 = $launcherPs1.Replace('__GATEWAY_BASE__', $GatewayBase).Replace('__PORT__', "$Port").Replace('__DATA_ROOT__', $DataRoot).Replace('__RELEASE_VERSION__', $releaseVersion)
    Set-Content -LiteralPath (Join-Path $InstallDir 'wt-launch.ps1') -Value $launcherPs1 -Encoding UTF8

    $cmdWrapper = "@echo off`r`nsetlocal`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0wt-launch.ps1`" %*`r`nendlocal`r`n"
    [IO.File]::WriteAllText((Join-Path $InstallDir 'wtstudio.cmd'), $cmdWrapper, [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $InstallDir 'wt.cmd'), $cmdWrapper, [Text.Encoding]::ASCII)

    $bgCmd = "@echo off`r`nset `"VIETDUB_DATA_ROOT=$DataRoot`"`r`nset `"VIETDUB_LICENSE_API_URL=$GatewayBase`"`r`nset `"VIETDUB_DEV_MODE=0`"`r`nset `"VIETDUB_ALLOWED_ORIGINS=http://127.0.0.1:$Port,http://localhost:$Port`"`r`ncd /d `"%~dp0vietdub-processor`"`r`n`"%~dp0vietdub-processor\vietdub-processor.exe`" _serve --host 127.0.0.1 --port $Port --no-browser --no-interactive`r`n"
    [IO.File]::WriteAllText((Join-Path $InstallDir 'wt-bg.cmd'), $bgCmd, [Text.Encoding]::ASCII)

    $bgLauncher = Join-Path $InstallDir 'wt-bg.cmd'
    $vbs = @"
Set shell = CreateObject("WScript.Shell")
On Error Resume Next
Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
http.setTimeouts 1000, 1000, 1000, 1000
alreadyRunning = False
http.open "GET", "http://127.0.0.1:$Port/api/health", False
http.send
If Err.Number = 0 Then
  If http.status = 200 Then alreadyRunning = True
End If
If Not alreadyRunning Then
  shell.Run Chr(34) & "$bgLauncher" & Chr(34), 0, False
  For i = 1 To 45
    Err.Clear
    http.open "GET", "http://127.0.0.1:$Port/api/health", False
    http.send
    If Err.Number = 0 Then
      If http.status = 200 Then Exit For
    End If
    WScript.Sleep 1000
  Next
End If
On Error GoTo 0
shell.Run "http://127.0.0.1:$Port/", 1, False
"@
    [IO.File]::WriteAllText((Join-Path $InstallDir 'open.vbs'), $vbs, [Text.Encoding]::Unicode)

    if (-not $SkipPath) {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $normDir = $InstallDir.TrimEnd('\')
        $entries = @($userPath -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ine $normDir })
        [Environment]::SetEnvironmentVariable('Path', ((@($InstallDir) + $entries) -join ';'), 'User')
        $curEntries = @($env:Path -split ';' | Where-Object { $_ })
        if (-not ($curEntries | Where-Object { $_.TrimEnd('\') -ieq $normDir })) {
            $env:Path = "$InstallDir;$env:Path"
        }
    }

    if (-not $SkipShortcut) {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut((Join-Path $desktop 'WT Studio.lnk'))
        $sc.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
        $sc.Arguments = '"' + (Join-Path $InstallDir 'open.vbs') + '"'
        $sc.WorkingDirectory = $InstallDir
        $sc.Description = 'WT Studio - Long tieng AI & Render Video'
        $sc.Save()
    }

    # Mode 2A: Write one-time delivery claim if WT_KEY provided
    if ($LicenseKey) {
        $deliveryJson = (@{ claim = $LicenseKey; key = $LicenseKey } | ConvertTo-Json -Compress)
        [IO.File]::WriteAllText((Join-Path $InstallDir 'wt-delivery.json'), $deliveryJson, (New-Object Text.UTF8Encoding($false)))
    }

    # [5/5] Start processor, verify health & activate license
    Write-Host "[5/5] Dang khoi dong WT Studio tren cong $Port va kiem tra ket noi..." -ForegroundColor Yellow
    $env:VIETDUB_DATA_ROOT = $DataRoot
    $env:VIETDUB_LICENSE_API_URL = $GatewayBase
    $env:VIETDUB_DEV_MODE = '0'
    $env:VIETDUB_ALLOWED_ORIGINS = "http://127.0.0.1:$Port,http://localhost:$Port"

    $stdoutLog = Join-Path $InstallDir 'runtime\processor-start.stdout.log'
    $stderrLog = Join-Path $InstallDir 'runtime\processor-start.stderr.log'
    try {
        Start-Process -WindowStyle Hidden -FilePath $processorExe `
            -ArgumentList @('_serve', '--host', '127.0.0.1', '--port', "$Port", '--no-browser', '--no-interactive') `
            -WorkingDirectory (Split-Path -Parent $processorExe) `
            -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -ErrorAction Stop | Out-Null
    } catch {
        if ($_.Exception.Message -match 'Application Control|blocked') {
            Write-Host ''
            Write-Host '======================================================================' -ForegroundColor Red
            Write-Host ' [!] CHU Y: Windows 11 Smart App Control dang chan chay ung dung!' -ForegroundColor Yellow
            Write-Host '----------------------------------------------------------------------' -ForegroundColor DarkGray
            Write-Host ' Cach mo khoa chi mat 10 giay:' -ForegroundColor White
            Write-Host " 1. Mo Start Menu, tim 'Smart App Control' va chuyen sang 'Off' (Tat)." -ForegroundColor Cyan
            Write-Host ' 2. Bam icon WT Studio ngoai Desktop hoac go: wtstudio' -ForegroundColor Green
            Write-Host '======================================================================' -ForegroundColor Red
            exit 0
        }
        throw
    }

    $healthy = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        try {
            $h = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/health" -TimeoutSec 2
            if ($h.status -eq 'ok') { $healthy = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
    if (-not $healthy) {
        throw "Bo xu ly WT Studio khong khoi dong duoc tren cong $Port. Kiem tra log: $stderrLog"
    }

    $activated = $false
    $activationMessage = ''
    try {
        $licStatus = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/license/status" -TimeoutSec 10
        if ($licStatus.valid) { $activated = $true }
    } catch {
        $activationMessage = $_.Exception.Message
    }

    if (-not $activated -and $LicenseKey) {
        try {
            $actBody = @{ key = $LicenseKey } | ConvertTo-Json -Compress
            $actRes = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/license/activate" -Method Post -ContentType 'application/json' -Body $actBody -TimeoutSec 12
            if ($actRes.valid) { $activated = $true }
        } catch {
            $errBody = ''
            try { $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream()); $errBody = $sr.ReadToEnd() } catch {}
            $activationMessage = if ($errBody) { $errBody } else { $_.Exception.Message }
        }
    }

    Write-Host ''
    Write-Host '======================================================================' -ForegroundColor Green
    Write-Host " [OK] CAI DAT WT STUDIO v$releaseVersion THANH CONG!" -ForegroundColor Green
    if ($activated) {
        Write-Host ' [OK] BAN QUYEN DA DUOC KICH HOAT - SAN SANG SU DUNG NGAY!' -ForegroundColor Green
    } elseif ($LicenseKey) {
        Write-Host " [!] Chua kich hoat duoc key tu dong: $activationMessage" -ForegroundColor Yellow
        Write-Host '     Ban co the nhap lai ma ban quyen truc tiep tren giao dien Web.' -ForegroundColor Yellow
    } else {
        Write-Host ' [!] Trinh duyet se mo man hinh nhap Ma ban quyen (License Key).' -ForegroundColor Yellow
        Write-Host '     Dan ma WTS-... ban nhan duoc sau thanh toan de mo khoa tool.' -ForegroundColor Yellow
    }
    Write-Host " -> Giao dien Web: http://127.0.0.1:$Port/" -ForegroundColor Cyan
    Write-Host ' -> Lan sau mo nhanh: Bam icon "WT Studio" ngoai Desktop hoac go: wtstudio' -ForegroundColor Cyan
    Write-Host ' -> Cap nhat ban moi: wtstudio update' -ForegroundColor DarkCyan
    Write-Host '======================================================================' -ForegroundColor Green

    if (-not $NoBrowser) {
        Start-Process "http://127.0.0.1:$Port/"
    }
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
