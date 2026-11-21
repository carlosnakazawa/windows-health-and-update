<#
.SYNOPSIS
    Deterministic verification harness for local development and CI.

.DESCRIPTION
    Runs repository guardrails in order:
      1. PowerShell AST syntax check on every .ps1 file
      2. Strict ASCII-only byte check on every .ps1 file (PS 5.1 safety)
      3. Project guardrail checks (no /ResetBase, no Write-Log shadowing, dot-source guards)
      4. PSScriptAnalyzer with PSScriptAnalyzerSettings.psd1 (unless -SkipAnalyzer)
      5. Pester 5.5+ test suite (unless -SkipPester)

.PARAMETER SkipAnalyzer
    Skips PSScriptAnalyzer (useful when the module is not installed locally).

.PARAMETER SkipPester
    Skips Pester unit tests.

.EXAMPLE
    .\scripts\Invoke-HarnessCheck.ps1
#>
[CmdletBinding()]
param(
    [switch] $SkipAnalyzer,
    [switch] $SkipPester
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath
$failures = New-Object -TypeName System.Collections.Generic.List[string]

$psFiles = @(Get-ChildItem -LiteralPath $repoRoot -Filter '*.ps1' -File -Recurse | Sort-Object -Property FullName)

Write-Output ('[1/5] Syntax check ({0} PowerShell files)...' -f $psFiles.Count)
foreach ($file in $psFiles) {
    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        $failures.Add("Syntax error in $($file.Name): $($parseErrors[0].Message)")
    }
}

Write-Output '[2/5] ASCII-only check...'
foreach ($file in $psFiles) {
    $nonAscii = @([System.IO.File]::ReadAllBytes($file.FullName) | Where-Object { $_ -gt 127 })
    if ($nonAscii.Count -gt 0) {
        $failures.Add("Non-ASCII bytes found in $($file.Name) ($($nonAscii.Count) byte(s)).")
    }
}

Write-Output '[3/5] Project guardrails check...'
$mainScriptPath = Join-Path -Path $repoRoot -ChildPath 'Invoke-WindowsMaintenance.ps1'
$schedulerScriptPath = Join-Path -Path $repoRoot -ChildPath 'Register-MaintenanceTask.ps1'

$mainLines = Get-Content -LiteralPath $mainScriptPath
foreach ($line in $mainLines) {
    if ($line -match '^\s*#') { continue }
    if ($line -match '/ResetBase') {
        $failures.Add('Guardrail violation: /ResetBase must not be used in Invoke-WindowsMaintenance.ps1.')
    }
    if ($line -match '^\s*function\s+Write-Log\b') {
        $failures.Add('Guardrail violation: function Write-Log shadows a built-in PowerShell cmdlet.')
    }
}

foreach ($entryScript in @($mainScriptPath, $schedulerScriptPath)) {
    $raw = Get-Content -LiteralPath $entryScript -Raw
    if ($raw -notmatch "MyInvocation\.InvocationName\s*-eq\s*'\.'") {
        $failures.Add("Guardrail violation: missing dot-source guard in $(Split-Path -Path $entryScript -Leaf).")
    }
}

if (-not $SkipAnalyzer) {
    Write-Output '[4/5] PSScriptAnalyzer...'
    if (-not (Get-Command -Name 'Invoke-ScriptAnalyzer' -ErrorAction SilentlyContinue)) {
        $failures.Add('PSScriptAnalyzer is not installed. Install it or pass -SkipAnalyzer.')
    }
    else {
        $settingsPath = Join-Path -Path $repoRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
        $issues = @(Invoke-ScriptAnalyzer -Path $repoRoot -Recurse -Settings $settingsPath)
        if ($issues.Count -gt 0) {
            $issues | Format-Table -AutoSize -Wrap | Out-String | Write-Output
            $failures.Add("PSScriptAnalyzer reported $($issues.Count) issue(s).")
        }
    }
}
else {
    Write-Output '[4/5] PSScriptAnalyzer skipped.'
}

if (-not $SkipPester) {
    Write-Output '[5/5] Pester unit tests...'
    $pesterModule = Get-Module -ListAvailable -Name 'Pester' | Where-Object { $_.Version -ge [version]'5.5.0' } | Select-Object -First 1
    if (-not $pesterModule) {
        $failures.Add('Pester 5.5.0+ is not installed. Install it or pass -SkipPester.')
    }
    else {
        Import-Module -Name 'Pester' -MinimumVersion '5.5.0' -Force
        $config = New-PesterConfiguration
        $config.Run.Path = (Join-Path -Path $repoRoot -ChildPath 'tests')
        $config.Run.PassThru = $true
        $config.Output.Verbosity = 'Normal'
        $testResult = Invoke-Pester -Configuration $config
        if ($testResult.FailedCount -gt 0) {
            $failures.Add("Pester reported $($testResult.FailedCount) failed test(s).")
        }
    }
}
else {
    Write-Output '[5/5] Pester skipped.'
}

if ($failures.Count -gt 0) {
    Write-Output ''
    Write-Output 'HARNESS CHECK FAILED:'
    foreach ($failure in $failures) {
        Write-Output "  - $failure"
    }
    exit 1
}

Write-Output ''
Write-Output 'HARNESS CHECK PASSED.'
exit 0
