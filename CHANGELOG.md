# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [2.0.0] - 2026-11-21

### Added

- Windows version, edition and servicing channel detection (Windows 10, Windows 11, LTSC, IoT, Windows Server).
- Support status check against Microsoft's lifecycle dates, with a warning 90 days before the end of updates.
- Steps that do not apply to the detected system are skipped with a reason (for example, no Microsoft Store on LTSC or Windows Server).
- System Restore point before any change.
- Windows Update download and installation through the Windows Update Agent API (previously only a scan was triggered).
- `-IncludeDrivers` and `-IncludeFeatureUpdates` switches.
- Microsoft Defender signature update and quick scan.
- Delivery Optimization cache cleanup, temp cleanup for every local profile, and a report of the space freed.
- Disk reliability counters (temperature, wear, uncorrected read errors) and low free space warnings.
- Windows 11 hardware readiness check on Windows 10.
- Pending restart detection, `-AutoReboot`, and exit code `3010` when a restart is required.
- `-Skip`, `-Only`, `-WhatIf` and `-Confirm`.
- JSON report next to the transcript, plus log retention.
- `Register-MaintenanceTask.ps1` to schedule the maintenance.
- Pester tests, PSScriptAnalyzer rules and a GitHub Actions workflow running on Windows Server 2022 and 2025 with Windows PowerShell 5.1 and PowerShell 7.

### Changed

- Logs moved from the Desktop to `%ProgramData%\WindowsHealthAndUpdate\Logs`, which also works when the Desktop is redirected to OneDrive or when the script runs as SYSTEM.
- Temporary files are only deleted when older than `-TempFileAgeDays` (default 2), so running installers are not affected.
- A failing step no longer stops the run: each step reports Success, Warning, Failed or Skipped.
- winget is located even when it is not on `PATH`, and its exit codes are interpreted.
- DISM and SFC are called through `Sysnative` when the script runs in 32-bit PowerShell.

### Removed

- `UsoClient StartInteractiveScan`: it is undocumented, returns immediately without reporting results and only starts a scan.

## [1.0.0]

### Added

- First version: winget upgrades, Store scan, Windows Update scan, DISM/SFC, component and temp cleanup, disk status.
