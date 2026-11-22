# AGENTS.md

Canonical instructions and guardrails for AI coding agents working in `windows-health-and-update`.

## Project Overview

`windows-health-and-update` is an open-source, version-aware Windows maintenance toolkit written in PowerShell.

| File | Responsibility |
| --- | --- |
| [Invoke-WindowsMaintenance.ps1](Invoke-WindowsMaintenance.ps1) | Main elevated maintenance script (OS/lifecycle detection + 9 isolated steps + transcript/JSON report). |
| [Register-MaintenanceTask.ps1](Register-MaintenanceTask.ps1) | Registers or removes the Windows Task Scheduler job with ACL and argument safety checks. |
| [tests/Invoke-WindowsMaintenance.Tests.ps1](tests/Invoke-WindowsMaintenance.Tests.ps1) | Pester 5.5+ unit, guardrail, ASCII, and documentation-link tests. |
| [scripts/Invoke-HarnessCheck.ps1](scripts/Invoke-HarnessCheck.ps1) | Deterministic local verification harness (AST parse, ASCII check, guardrails, PSScriptAnalyzer, Pester). |
| [PSScriptAnalyzerSettings.psd1](PSScriptAnalyzerSettings.psd1) | Static analysis rules enforcing PowerShell 5.1 and 7.4 syntax compatibility. |
| [.github/workflows/ci.yml](.github/workflows/ci.yml) | CI matrix: PSScriptAnalyzer + Pester + `-WhatIf` smoke test on Windows Server 2022/2025 x PS 5.1/7. |
| [README.md](README.md) & `docs/README.*.md` | Documentation in 10 languages (`README.md` is the canonical reference). |
| [SECURITY.md](SECURITY.md) | Vulnerability disclosure policy and elevated-execution security notes. |

## Non-Negotiable Guardrails

### 1. Security (Elevated Execution)
This codebase runs **as Administrator** and registers an elevated scheduled task. Treat every filesystem and argument boundary as a privilege-escalation surface:
- **No symlink/junction traversal (CWE-59):** Never use `Get-ChildItem -Recurse` or `Remove-Item` blindly on user-writable directories (`Temp`, `%ProgramData%`). Always skip `ReparsePoint` attributes.
- **No command injection:** Never concatenate unvalidated user strings into elevated command lines. Keep `Test-SafeMaintenanceArgument` strict.
- **No weakened ACL checks:** Keep `Test-IsPathUserWritable` checking atomic `FileSystemRights` write/takeover bits (`WriteData`, `AppendData`, `Delete`, `ChangePermissions`, `TakeOwnership`, etc.) — never bitwise-OR composite flags like `FullControl` or `Modify`, which include `Read` bits.
- **Scope boundary (non-destructive by design):** Never add registry "tweaks", debloating, telemetry/service disabling, `DISM /ResetBase`, or deletion of user files, Downloads, or the Recycle Bin.
- **Single instance:** The entry point takes the `Global\WindowsHealthAndUpdate` lock (`Enter-MaintenanceLock`) right after the elevation check. Never move steps, log directory creation or cleanup before it, and keep the owner check that ignores locks created by untrusted accounts.
- **Safe agent execution:** Never run `Invoke-WindowsMaintenance.ps1` or `Register-MaintenanceTask.ps1` live without `-WhatIf`, and never execute `shutdown` or destructive system commands unless the user explicitly asks for a live run.

### 2. PowerShell 5.1 & Encoding Compatibility
- **ASCII-only `.ps1` files:** Every `.ps1` file must contain only ASCII bytes (`<= 127`). Windows PowerShell 5.1 reads BOM-less UTF-8 files using the system ANSI code page.
- **PS 5.1 + PS 7+ syntax:** Do not use PowerShell 7-only syntax (`??`, `??=`, `?.`, ternary `?:`, `&&`, `||`, `-Parallel`).
- **Dot-source safety:** Entry-point scripts must keep `if ($MyInvocation.InvocationName -eq '.') { return }` so Pester can load functions without side effects, and must not evaluate `$PSScriptRoot` inside `param()` default expressions (which fails when dot-sourced in PS 5.1).
- **Strict `-WhatIf` contract:** Running with `-WhatIf` must not delete files (e.g. `Clear-OldLog`) or mutate system state.
- **No built-in cmdlet shadowing:** Never define functions that collide with built-in cmdlets across PS 5.1 or PS 7 (e.g. `Write-Log`). Use approved verbs and singular nouns (`PSScriptAnalyzer`).

### 3. Windows Lifecycle & Documentation
- **Lifecycle data:** Dates in `Get-WindowsLifecycleData` must come from Microsoft's official [Windows release health](https://learn.microsoft.com/windows/release-health/) pages. Update the support table in [README.md](README.md) when adding releases.
- **Documentation links:** Whenever you add or rename markdown files or languages, ensure all relative links resolve and all language READMEs cross-link each other (enforced by Pester).
- **No stray artifacts:** Never commit `.log` files, `maintenance_*.json` reports, or local IDE files.

## Verification Harness (Run Before Finishing)

Always run the deterministic verification harness after edits:

```powershell
# Fast static checks (AST parse, ASCII-only, guardrails)
.\scripts\Invoke-HarnessCheck.ps1 -SkipAnalyzer -SkipPester

# Full local verification (requires PSScriptAnalyzer 1.25.0 and Pester 5.5+)
.\scripts\Invoke-HarnessCheck.ps1
```

Before opening or updating a PR:
1. All static checks, `PSScriptAnalyzer` (0 issues), and `Pester` tests must pass.
2. Any new logic or bug fix must include a corresponding Pester test (use `Mock` for OS/WMI/native-command interactions).
3. Keep commits focused, with clear messages in English.
