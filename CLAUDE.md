# CLAUDE.md

@AGENTS.md

## Claude Code Harness Notes

- Treat [AGENTS.md](AGENTS.md) as the single source of truth for architecture, guardrails, and verification commands. Do not duplicate or diverge from those rules here.
- Before committing or pushing, run `.\scripts\Invoke-HarnessCheck.ps1` (or at minimum `-SkipAnalyzer -SkipPester` if modules are unavailable locally, then verify the GitHub Actions CI run).
- Never invoke `Invoke-WindowsMaintenance.ps1` or `Register-MaintenanceTask.ps1` without `-WhatIf` during development or testing unless explicitly instructed by the user.
- When reviewing or editing PowerShell code, verify both Windows PowerShell 5.1 and PowerShell 7 (`pwsh`) behavior — especially around `PSScriptAnalyzer` rules (`PSAvoidOverwritingBuiltInCmdlets`, `PSUseSingularNouns`, `PSUseCompatibleSyntax`).
