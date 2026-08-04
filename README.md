# WTStudio — Official Windows Distribution

WTStudio is an automated desktop application for video translation, dubbing, and AI processing.

## One-Command Installation (Windows)

Open PowerShell (no Administrator rights required) and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm 'https://raw.githubusercontent.com/wtrg/wtstudio-distribution/main/install.ps1' | iex"
```

## Running WTStudio

After installation completes, open a **NEW** Command Prompt (CMD) or PowerShell window and run:

```cmd
wtstudio
```

## Available Subcommands

- `wtstudio` — Launch WTStudio (prompts for activation key if unlicensed)
- `wtstudio activate` — Enter a new license key
- `wtstudio license-status` — Check license status & expiry
- `wtstudio deactivate` — Deactivate current machine registration
- `wtstudio --help` — Show help message

## Uninstallation

To remove WTStudio and clean up PATH environment variables:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\WTStudio\uninstall.ps1"
```

## Troubleshooting & SmartScreen Warning

Executables in this distribution are built automatically via GitHub Actions. If Windows SmartScreen displays a warning, click **More info** -> **Run anyway**.
