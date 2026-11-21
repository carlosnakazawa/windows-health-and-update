## Summary

<!-- Describe what changed and why. -->

## Checklist

- [ ] `.ps1` files are **ASCII-only** and compatible with **Windows PowerShell 5.1** and **PowerShell 7+**
- [ ] `.\scripts\Invoke-HarnessCheck.ps1` passes (AST parse, ASCII, guardrails, `PSScriptAnalyzer`, `Pester`)
- [ ] Added or updated Pester unit tests for logic changes
- [ ] Security guardrails respected (no symlink/junction traversal, no unvalidated elevated arguments, `-WhatIf` makes no destructive changes)
- [ ] Updated [README.md](README.md) / [CHANGELOG.md](CHANGELOG.md) if user-facing behavior or parameters changed
- [ ] If Windows lifecycle dates changed, linked the official Microsoft Release Health source

## Testing

- Windows version / build:
- PowerShell version:
- Commands run:
