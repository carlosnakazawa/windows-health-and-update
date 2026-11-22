# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Single-instance lock: a manual run that starts while the scheduled task is running (or the other way round) stops before touching anything and exits with `170`. It uses a named mutex in the `Global` namespace, which Windows releases if a run is killed, so no stale lock is left behind; the next run notes that the previous one was interrupted. A lock created by an untrusted account (for example a standard user trying to block maintenance), or one that hides its owner, is ignored with a warning. `-WhatIf` is never blocked. Thanks to community feedback.
- `lock` in the JSON report: lock status and whether the previous run was interrupted.

- The JSON report lists every Windows update found (`steps[].Details`): title, KB, update ID, result (`Installed`, `InstalledWithErrors`, `Failed`, `Aborted`, `DownloadFailed`, `NotInstalled`), reason, HRESULT and whether it needs a restart. After an unattended run you can tell what was installed, what failed and why. Thanks to community feedback on the overnight-run scenario.
- `rebootScheduled` in the JSON report: `true` only when `-AutoReboot` actually scheduled the restart.
- The Windows Update step message names the failed updates and says when a restart is required, for example `1 installed, 1 failed (KB5070002). Restart required.`

### Changed

- The report is written after the restart is scheduled, so it reflects whether that happened.
- Documented that exit code `1` can also mean a restart is pending; the JSON report is the complete source.

### Fixed

- Remote sessions (WinRM/SSH) now get the explanation about `0x80070005`. The previous `catch [COMException]` never matched, because .NET turns `E_ACCESSDENIED` into `UnauthorizedAccessException`.
- A batch-wide download or install error no longer drops the list of updates: each one is reported with the HRESULT.
- Error messages include the HRESULT of COM errors that PowerShell wraps in `MethodInvocationException`, for example a failing Windows Update search.

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
- `Register-MaintenanceTask.ps1` to schedule the maintenance, with an ACL check on the script folder and validation of `-MaintenanceArguments`.
- `SECURITY.md` with a private vulnerability reporting policy.
- Pester tests, PSScriptAnalyzer rules and a GitHub Actions workflow running on Windows Server 2022 and 2025 with Windows PowerShell 5.1 and PowerShell 7.

### Changed

- Logs moved from the Desktop to `%ProgramData%\WindowsHealthAndUpdate\Logs`, which also works when the Desktop is redirected to OneDrive or when the script runs as SYSTEM.
- Temporary files are only deleted when older than `-TempFileAgeDays` (default 2), so running installers are not affected.
- A failing step no longer stops the run: each step reports Success, Warning, Failed or Skipped.
- winget is located even when it is not on `PATH`, and its exit codes are interpreted. Only packages with a known installed version are upgraded (no `--include-unknown`), which avoids repeated reinstalls.
- `-Skip` and `-Only` also accept a comma-separated string (`-Skip Repair,Defender`), which is how `powershell.exe -File` passes lists from Task Scheduler, `cmd.exe` or deployment tools.
- Temp and log cleanup never follow symbolic links or junctions.
- DISM and SFC are called through `Sysnative` when the script runs in 32-bit PowerShell.

### Removed

- `UsoClient StartInteractiveScan`: it is undocumented, returns immediately without reporting results and only starts a scan.

## [1.0.0]

### Added

- First version: winget upgrades, Store scan, Windows Update scan, DISM/SFC, component and temp cleanup, disk status.
