# Windows Health & Update

[![CI](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml/badge.svg)](https://github.com/carlosnakazawa/windows-health-and-update/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell&logoColor=white)
![Windows 10 | 11 | Server](https://img.shields.io/badge/Windows-10%20%7C%2011%20%7C%20Server-0078D4)

**English** | [Português (Brasil)](docs/README.pt-BR.md) | [Español](docs/README.es.md) | [Français](docs/README.fr.md) | [Deutsch](docs/README.de.md) | [Italiano](docs/README.it.md) | [Русский](docs/README.ru.md) | [日本語](docs/README.ja.md) | [한국어](docs/README.ko.md) | [简体中文](docs/README.zh-CN.md)

A PowerShell maintenance script that keeps a Windows PC up to date and healthy with one command: application updates, Windows Update, Microsoft Defender, system file repair, cleanup and disk health.

It **detects the exact Windows release** (for example *Windows 11 Pro 25H2*, *Windows 10 Enterprise LTSC 2021* or *Windows Server 2022*), tells you **whether that release still gets security updates**, and **adapts each step** to it.

```text
=== Windows Health & Update v2.0.0 ===
[10:00:01]      System     : Windows 11 Home Single Language, version 26H2 (OS build 26300.9974, AMD64)
[10:00:01] OK   Support    : Supported until 2028-10-10 (689 days left).
...
=== Summary ===
[10:41:12] OK   RestorePoint      Success  00:00:21  Restore point #42 created.
[10:41:12] OK   WinGet            Success  00:04:10  Applications are up to date.
[10:41:12]      Store             Skipped  00:00:00  Skipped with -Skip.
[10:41:12] OK   WindowsUpdate     Success  00:12:35  3 installed, 0 failed.
[10:41:12] WARN DiskHealth        Warning  00:00:02  drive D: only 8.2% free
```

## Features

| Step | What it does |
| --- | --- |
| `RestorePoint` | Creates a System Restore point before anything changes. |
| `WinGet` | Upgrades installed applications with known versions silently with `winget` (accepts package/source agreements automatically). Finds winget even when it is not on `PATH` (SYSTEM account, a different admin user). |
| `Store` | Triggers a Microsoft Store app update scan. |
| `WindowsUpdate` | Searches, downloads and **installs** updates through the Windows Update Agent API (accepts update EULAs automatically). Drivers and feature updates are opt-in. Note: the WUA API blocks remote WinRM/SSH sessions (`0x80070005`); run locally or via a scheduled task. |
| `Defender` | Updates Microsoft Defender signatures and runs a quick scan. Skipped when another antivirus is active. |
| `Repair` | `DISM /RestoreHealth` followed by `sfc /scannow`. |
| `Cleanup` | `DISM /StartComponentCleanup`, temp files older than N days for every local profile, Delivery Optimization cache. Reports the space freed. |
| `DiskHealth` | Disk health, temperature, wear and uncorrected read errors, plus free space per volume. |
| `UpgradeReadiness` | Windows 10 only: checks TPM 2.0, UEFI/Secure Boot, RAM, storage and CPU basics for Windows 11. |

The script also:

- detects a **pending restart** before and after the run and can restart automatically (`-AutoReboot`);
- isolates every step: a failure is reported and the next step still runs;
- writes a **transcript** and a **JSON report** to `%ProgramData%\WindowsHealthAndUpdate\Logs`, with retention;
- supports `-WhatIf` and `-Confirm`;
- returns exit codes that automation tools understand: `0` success, `1` failure, `3010` restart required;
- reports each Windows update individually (title, KB, result, error code, restart need) in the JSON report.

## Supported Windows versions

The script works out what it is running on and adjusts. Steps marked "n/a" are skipped with an explanation.

| Step | Windows 11 Home/Pro | Windows 11 Enterprise/Education | Windows 10 22H2 | Windows 10/11 LTSC | Windows Server 2016-2025 |
| --- | :---: | :---: | :---: | :---: | :---: |
| Support status check | yes | yes | yes (ESU note) | yes | yes |
| RestorePoint | yes | yes | yes | yes | n/a |
| WinGet | yes | yes | yes ¹ | if installed ¹ | if installed ¹ |
| Store | yes | yes | yes | n/a | n/a |
| WindowsUpdate | yes | yes | yes | yes | yes |
| Defender | yes ² | yes ² | yes ² | yes ² | yes ² |
| Repair / Cleanup / DiskHealth | yes | yes | yes | yes | yes |
| UpgradeReadiness | n/a | n/a | yes | n/a | n/a |

¹ Requires [App Installer](https://aka.ms/getwinget). If it is missing, the step is skipped.
² Only when Microsoft Defender is the active antivirus.

### Support status

Release end dates come from Microsoft's [Windows release health](https://learn.microsoft.com/windows/release-health/) pages (reviewed November 2026). As of that date:

| Release | Build | Home/Pro | Enterprise/Education |
| --- | --- | --- | --- |
| Windows 11 26H2 | 26300 | 2028-10-10 | 2029-10-09 |
| Windows 11 26H1 (new devices only) | 28000 | 2028-03-14 | 2029-03-13 |
| Windows 11 25H2 | 26200 | 2027-10-12 | 2028-10-10 |
| Windows 11 24H2 | 26100 | **ended 2026-10-13** | 2027-10-12 |
| Windows 11 23H2 and older | 22631- | ended | ended |
| Windows 10 22H2 | 19045 | **ended 2025-10-14** (ESU only) | ended (ESU only) |

LTSC and Windows Server releases are covered as well. See `Get-WindowsLifecycleData` in the script for the complete table.

### How the version is detected

The registry value `ProductName` still reads **"Windows 10"** on Windows 11, so the script does not rely on it. It reads `CurrentBuild`, `UBR`, `DisplayVersion`, `EditionID` and `InstallationType` from `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` and derives:

- **family**: Windows Server when `InstallationType` is `Server`/`Server Core`, Windows 11 from build 22000, otherwise Windows 10;
- **servicing track**: Home/Pro (24 months), Enterprise/Education (36 months), LTSC, IoT LTSC or Server. This decides which end date applies. For example, build 26100 is Windows 11 24H2, Windows 11 LTSC 2024 *or* Windows Server 2025, each with a different end date.

## Requirements

- Windows 10, Windows 11 or Windows Server 2016+
- Windows PowerShell 5.1 (built in) or PowerShell 7+
- An elevated session (Run as administrator)

## Quick start

1. Download or clone the repository, for example to `C:\Program Files\WindowsHealthAndUpdate`.
2. Open **Windows Terminal** or **PowerShell** as **Administrator**.
3. Run the script. `-ExecutionPolicy Bypass` applies only to this process and changes no system setting:

   ```powershell
   cd 'C:\Program Files\WindowsHealthAndUpdate'
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-WindowsMaintenance.ps1
   ```

   If you downloaded the ZIP, you can unblock the files first with `Get-ChildItem -Recurse | Unblock-File`.

Preview what would happen, without changing anything:

```powershell
.\Invoke-WindowsMaintenance.ps1 -WhatIf
```

## Usage

```powershell
# Everything that applies to this PC
.\Invoke-WindowsMaintenance.ps1

# Quick pass: skip DISM/SFC and the Defender scan
.\Invoke-WindowsMaintenance.ps1 -Skip Repair, Defender

# Only updates, then restart if needed
.\Invoke-WindowsMaintenance.ps1 -Only WinGet, WindowsUpdate -AutoReboot

# Include drivers and move to the latest Windows 11 version
.\Invoke-WindowsMaintenance.ps1 -IncludeDrivers -IncludeFeatureUpdates

# Keep logs on the Desktop
.\Invoke-WindowsMaintenance.ps1 -LogDirectory ([Environment]::GetFolderPath('Desktop'))

# Full help
Get-Help .\Invoke-WindowsMaintenance.ps1 -Detailed
```

| Parameter | Default | Description |
| --- | --- | --- |
| `-Skip` | none | Steps to skip. |
| `-Only` | all | Run only these steps. |
| `-IncludeDrivers` | off | Also install driver updates from Windows Update. |
| `-IncludeFeatureUpdates` | off | Also install feature updates (for example 24H2 to 25H2). |
| `-AutoReboot` | off | Restart 2 minutes after the run when needed (`shutdown /a` cancels). |
| `-TempFileAgeDays` | `2` | Only delete temp files older than this. |
| `-LogDirectory` | `%ProgramData%\WindowsHealthAndUpdate\Logs` | Where transcripts and JSON reports go. |
| `-LogRetentionDays` | `30` | Delete older logs and reports. |
| `-WhatIf` / `-Confirm` | | Preview, or confirm each step. |

## Scheduling

`Register-MaintenanceTask.ps1` creates a Task Scheduler task that runs as your user, elevated, only while you are signed in, so no password is stored. If the PC was off at the scheduled time, the task runs as soon as possible.

```powershell
# Every Sunday at 10:00 (default)
.\Register-MaintenanceTask.ps1

# Every day at 12:30, updates only
.\Register-MaintenanceTask.ps1 -Frequency Daily -At 12:30 -MaintenanceArguments '-Only WinGet, WindowsUpdate'

# Remove the task
.\Register-MaintenanceTask.ps1 -Unregister
```

> **Security:** the task runs the script with administrator rights. Keep it in a folder standard users cannot modify (such as `C:\Program Files\...`). Otherwise any process running as your user could edit the script and gain elevation. The registration script checks the folder/file ACLs and warns you when standard users have write access. See [SECURITY.md](SECURITY.md) for more details.

## Logs and report

Each run creates two files in the log directory:

- `maintenance_<timestamp>.log`: PowerShell transcript;
- `maintenance_<timestamp>.json`: structured report with OS details, support status, the result of each step, restart status and exit code. You can collect it from several machines or feed it to monitoring.

For Windows Update, the report lists **every update found**, so after an unattended run you can tell what was installed, what failed and whether a restart is still needed:

```json
"steps": [{
  "Step": "WindowsUpdate",
  "Status": "Warning",
  "Message": "1 installed, 1 failed (KB5070002). Restart required.",
  "Details": [
    { "Title": "2026-11 Cumulative Update", "KB": "KB5070001", "Result": "Installed", "HResult": null, "RebootRequired": true },
    { "Title": "Servicing Stack Update", "KB": "KB5070002", "Result": "Failed", "HResult": "0x80240022", "RebootRequired": false }
  ]
}],
"rebootRequired": true,
"rebootScheduled": false
```

- `Result`: `Installed`, `InstalledWithErrors`, `Failed`, `Aborted`, `DownloadFailed`, or `NotInstalled` with a `Reason` (`Optional`, `FeatureUpdate`, `NeedsUserInput`).
- `HResult`: the Windows Update error code, to look up in [Windows Update error codes](https://learn.microsoft.com/windows/deployment/update/windows-update-error-reference).
- `rebootScheduled`: `true` only when `-AutoReboot` actually scheduled the restart; `rebootRequired` alone means it is still pending.

Read the latest report:

```powershell
$latest = Get-ChildItem "$env:ProgramData\WindowsHealthAndUpdate\Logs\maintenance_*.json" | Sort-Object LastWriteTime | Select-Object -Last 1
$report = Get-Content -LiteralPath $latest.FullName -Raw | ConvertFrom-Json
$report.steps | Where-Object Step -eq 'WindowsUpdate' | Select-Object -ExpandProperty Details | Format-Table Title, KB, Result, HResult, RebootRequired
"Restart required: $($report.rebootRequired) (scheduled: $($report.rebootScheduled))"
```

> **Exit code `1` can also mean a restart is pending.** A single exit code cannot say "something failed" and "restart required" at the same time, so a failure wins. Check `rebootRequired` in the report.

DISM and SFC keep their own detailed logs in `%windir%\Logs\DISM\dism.log` and `%windir%\Logs\CBS\CBS.log`.

## What the script does not do

- No registry "tweaks", debloating, telemetry changes or service changes.
- No `DISM /ResetBase`: installed updates remain uninstallable.
- No deletion of user files, Downloads or the Recycle Bin. Only temp folders, and only files older than `-TempFileAgeDays`.
- No data sent anywhere.

## Development

```powershell
# Unit tests (Pester 5+)
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Invoke-Pester ./tests -Output Detailed

# Static analysis
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

The CI workflow runs the analyzer, the unit tests and a `-WhatIf` smoke test on **Windows Server 2022 and 2025**, with both **Windows PowerShell 5.1 and PowerShell 7**.

The script files are kept **ASCII-only** on purpose: Windows PowerShell 5.1 reads BOM-less files with the ANSI code page, so accented characters would break it. A test enforces this.

## Contributing

Feedback, bug reports and translations are welcome, in any language. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Roadmap

- Optional email/Teams/webhook notification with the JSON report.
- Hardware CPU compatibility list for the Windows 11 readiness check.
- Publish to the PowerShell Gallery.

## License

[MIT](LICENSE) © Carlos Alberto Nakazawa
