# Security Policy

## Supported Versions

Security fixes are provided for the latest `2.x` release on the `main` branch.

## Reporting a Vulnerability

Because `Invoke-WindowsMaintenance.ps1` and `Register-MaintenanceTask.ps1` run with **Administrator** privileges, please do **not** report security vulnerabilities through public GitHub issues.

Instead, report them privately using [GitHub Security Advisories](https://github.com/carlosnakazawa/windows-health-and-update/security/advisories/new).

Please include:

- a description of the vulnerability and its potential impact;
- steps to reproduce (Windows version, PowerShell version, and command used);
- any suggested mitigation or fix, if you have one.

## Security Considerations for Users

- **Install location for scheduled tasks:** When using `Register-MaintenanceTask.ps1`, place the scripts in a directory that standard users cannot modify (for example, `C:\Program Files\WindowsHealthAndUpdate`). Placing an elevated scheduled script inside a user-writable directory allows any process running as that user to escalate privileges.
- **Third-party updates:** `Invoke-WindowsMaintenance.ps1` invokes `winget` and the Windows Update Agent API to install updates and accepts update/package agreements automatically for unattended execution. Review the parameters (`-Skip`, `-Only`, `-WhatIf`, `-Confirm`) if you need tighter control.
