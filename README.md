# WTStudio

**WTStudio** is a local-first AI-powered video translation and dubbing studio for Windows.

Translate and dub videos from one language to another using local AI models — no cloud API required.

---

## Requirements

- Windows 10 / 11 (64-bit)
- No Python required
- No administrator privileges required
- No Git, Docker, or .NET SDK required

---

## Install (one command)

Open **PowerShell** and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm 'https://raw.githubusercontent.com/wtrg/wtstudio-distribution/main/install.ps1' | iex"
```

This will:
1. Download `WTStudio-Portable-Windows.zip` from the latest release
2. Verify SHA-256 checksum
3. Validate package manifest
4. Extract to `%LOCALAPPDATA%\WTStudio`
5. Create the `wtstudio` command in your User PATH

> **SmartScreen warning:** Windows may show "Unknown publisher" on first run.  
> Click **More info** → **Run anyway**. This is expected for unsigned community software.

---

## Usage

Open a **new** terminal window after installation:

```powershell
# Launch Local Web Studio (127.0.0.1:8765)
wtstudio

# Launch PySide6 Desktop application
wtstudio desktop

# Check Web Studio server status
wtstudio status

# Stop Web Studio server
wtstudio stop

# Check license status
wtstudio license-status

# Activate license
wtstudio activate

# Show help
wtstudio --help
```

---

## Activate

On first launch, WTStudio will prompt for license activation.  
Follow the on-screen instructions to enter your license key.

---

## Verify Checksum

Download `SHA256SUMS.txt` from the release page and verify manually:

```powershell
$hash = (Get-FileHash WTStudio-Portable-Windows.zip -Algorithm SHA256).Hash.ToLower()
$expected = (Select-String -Path SHA256SUMS.txt -Pattern "WTStudio-Portable-Windows.zip").Line.Split(' ')[0]
if ($hash -eq $expected) { "OK" } else { "MISMATCH" }
```

---

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\WTStudio\bin\uninstall.ps1"
```

Or download and run `uninstall.ps1` from the latest release.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| `wtstudio` not found | Open a NEW terminal after install; check User PATH includes `%LOCALAPPDATA%\WTStudio\bin` |
| SmartScreen blocks app | Click More info → Run anyway |
| Web Studio doesn't open | Run `wtstudio status` or `wtstudio license-status` in terminal to see errors |
| Checksum mismatch | Re-download; if persistent, open an issue |

---

## Security

See [SECURITY.md](SECURITY.md) for the vulnerability disclosure policy.

---

## License

WTStudio is released under GPL-3.0. See the LICENSE file in the installed bundle for details.

---

*WTStudio v4.05.4 — Distribution repository (installer only, no source code)*