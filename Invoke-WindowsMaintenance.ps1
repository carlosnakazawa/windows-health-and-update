<#
.SYNOPSIS
    Keeps Windows 10, Windows 11 and Windows Server up to date and healthy, adapting
    every step to the detected Windows version, edition and servicing channel.

.DESCRIPTION
    Invoke-WindowsMaintenance detects the exact Windows release (for example
    "Windows 11 Pro 25H2" or "Windows 10 Enterprise LTSC 2021"), checks whether that
    release still receives security updates, and then runs a sequence of maintenance
    steps. Steps that do not apply to the detected system - such as Microsoft Store
    updates on LTSC or Windows Server - are skipped with an explanation.

    Steps, in execution order:
      RestorePoint      Creates a System Restore point before any change is made.
      WinGet            Upgrades installed applications with winget.
      Store             Triggers a Microsoft Store app update scan.
      WindowsUpdate     Searches, downloads and installs Windows updates (WUA COM API).
      Defender          Updates Microsoft Defender signatures and runs a quick scan.
      Repair            Runs DISM /RestoreHealth followed by SFC /scannow.
      Cleanup           Cleans the component store, temp folders and Delivery Optimization cache.
      DiskHealth        Reports disk health, reliability counters and free space.
      UpgradeReadiness  Windows 10 only: checks the main Windows 11 hardware requirements.

    A transcript (.log) and a machine-readable report (.json) are written to -LogDirectory.

.PARAMETER Skip
    One or more steps to skip. Valid values: RestorePoint, WinGet, Store, WindowsUpdate,
    Defender, Repair, Cleanup, DiskHealth, UpgradeReadiness.

.PARAMETER Only
    Runs only the listed steps. Accepts the same values as -Skip.

.PARAMETER LogDirectory
    Folder for transcripts and JSON reports.
    Default: %ProgramData%\WindowsHealthAndUpdate\Logs

.PARAMETER LogRetentionDays
    Transcripts and reports older than this many days are deleted. Default: 30.

.PARAMETER TempFileAgeDays
    Only temporary files older than this many days are deleted, so files that running
    installers still need are left alone. Default: 2.

.PARAMETER IncludeDrivers
    Also installs driver updates offered by Windows Update. By default only software
    updates (cumulative, security, .NET, Defender platform...) are installed.

.PARAMETER IncludeFeatureUpdates
    Also installs Windows feature updates (for example 24H2 -> 25H2). They are excluded
    by default because they are large and change the Windows version.

.PARAMETER AutoReboot
    Restarts the computer two minutes after completion when a restart is required.
    The restart can be cancelled with: shutdown /a

.EXAMPLE
    .\Invoke-WindowsMaintenance.ps1

    Runs every step that applies to this computer.

.EXAMPLE
    .\Invoke-WindowsMaintenance.ps1 -Skip Repair, Defender

    Faster pass without DISM/SFC and without the Defender quick scan.

.EXAMPLE
    .\Invoke-WindowsMaintenance.ps1 -Only WindowsUpdate, WinGet -AutoReboot

    Installs pending Windows and application updates, then restarts if needed.

.EXAMPLE
    .\Invoke-WindowsMaintenance.ps1 -WhatIf

    Shows the detected Windows version, its support status and which steps would run,
    without changing anything.

.OUTPUTS
    None. Progress is written to the console, a transcript and a JSON report.
    Exit codes:
      0     Success (warnings may have been reported).
      1     At least one step failed, or the script is not running elevated.
      3010  Success, but a restart is required to finish.

.NOTES
    Author  : Carlos Alberto Nakazawa
    Version : 2.0.0
    Requires: Windows PowerShell 5.1 or PowerShell 7+, run as administrator.
    This file is intentionally ASCII-only: Windows PowerShell 5.1 reads BOM-less files
    using the system ANSI code page.

.LINK
    https://github.com/carlosnakazawa/windows-health-and-update
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('RestorePoint', 'WinGet', 'Store', 'WindowsUpdate', 'Defender', 'Repair', 'Cleanup', 'DiskHealth', 'UpgradeReadiness')]
    [string[]] $Skip = @(),

    [ValidateSet('RestorePoint', 'WinGet', 'Store', 'WindowsUpdate', 'Defender', 'Repair', 'Cleanup', 'DiskHealth', 'UpgradeReadiness')]
    [string[]] $Only = @(),

    [ValidateNotNullOrEmpty()]
    [string] $LogDirectory = (Join-Path -Path $env:ProgramData -ChildPath 'WindowsHealthAndUpdate\Logs'),

    [ValidateRange(1, 3650)]
    [int] $LogRetentionDays = 30,

    [ValidateRange(0, 365)]
    [int] $TempFileAgeDays = 2,

    [switch] $IncludeDrivers,

    [switch] $IncludeFeatureUpdates,

    [switch] $AutoReboot
)

$ScriptVersion = '2.0.0'

#region Output helpers ---------------------------------------------------------

function Write-MaintenanceLog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive tool: colored console output, captured by Start-Transcript.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string] $Message,

        [ValidateSet('Info', 'Header', 'Success', 'Warning', 'Error', 'Detail')]
        [string] $Level = 'Info'
    )

    if ($Level -eq 'Header') {
        Write-Host ''
        Write-Host "=== $Message ===" -ForegroundColor Cyan
        return
    }

    $style = @{
        Info    = @('Gray', '    ')
        Success = @('Green', 'OK  ')
        Warning = @('Yellow', 'WARN')
        Error   = @('Red', 'FAIL')
        Detail  = @('DarkGray', '    ')
    }[$Level]

    Write-Host ('[{0}] {1} {2}' -f (Get-Date -Format 'HH:mm:ss'), $style[1], $Message) -ForegroundColor $style[0]
}

function New-StepResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only builds an in-memory object.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Success', 'Warning', 'Failed', 'Skipped')]
        [string] $Status,

        [string] $Message = '',

        [switch] $RebootRequired
    )

    $result = [pscustomobject]@{
        Status         = $Status
        Message        = $Message
        RebootRequired = [bool]$RebootRequired
        Duration       = [timespan]::Zero
    }
    $result.PSObject.TypeNames.Insert(0, 'WindowsMaintenance.StepResult')
    $result
}

function Format-ErrorRecord {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $exception = $ErrorRecord.Exception
    $message = ($exception.Message -replace '\s+', ' ').Trim()

    # COM errors (Windows Update Agent) are only useful with their HRESULT.
    if ($exception -is [System.Runtime.InteropServices.COMException] -and $message -notmatch '0x[0-9A-Fa-f]{8}') {
        $message = '{0} (0x{1:X8})' -f $message, $exception.HResult
    }
    $message
}

#endregion

#region Environment detection ------------------------------------------------

function Test-IsAdministrator {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $identity
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-NativeSystemPath {
    # A 32-bit PowerShell on 64-bit Windows is redirected from System32 to SysWOW64,
    # where SFC cannot start its repair service. "Sysnative" reaches the real System32.
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        return (Join-Path -Path $env:SystemRoot -ChildPath 'Sysnative')
    }
    Join-Path -Path $env:SystemRoot -ChildPath 'System32'
}

function ConvertTo-WindowsVersionInfo {
    <#
        Pure function: turns raw registry values into a normalized description of the OS.
        Kept separate from Get-WindowsVersionInfo so it can be unit tested.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [int] $Build,

        [int] $Revision = 0,

        [string] $DisplayVersion = '',

        [Parameter(Mandatory = $true)]
        [string] $EditionId,

        [string] $InstallationType = 'Client',

        [string] $ProductName = '',

        [string] $Architecture = ''
    )

    $isServer = $InstallationType -like 'Server*'

    # The registry "ProductName" still says "Windows 10" on Windows 11, so the family
    # has to be derived from the build number (Windows 11 starts at build 22000).
    if ($isServer) {
        $family = 'Windows Server'
    }
    elseif ($Build -ge 22000) {
        $family = 'Windows 11'
    }
    else {
        $family = 'Windows 10'
    }

    # Servicing track decides how long a release is supported.
    if ($isServer) {
        $track = 'Server'
    }
    elseif ($EditionId -match '^IoTEnterpriseS') {
        $track = 'IoTLTSC'
    }
    elseif ($EditionId -match '^EnterpriseS') {
        $track = 'LTSC'
    }
    elseif ($EditionId -match '^(Enterprise|Education|IoTEnterprise|ServerRdsh)') {
        $track = 'EnterpriseEducation'
    }
    else {
        $track = 'HomePro'
    }

    $edition = switch -Regex ($EditionId) {
        '^CoreSingleLanguage' { 'Home Single Language'; break }
        '^CoreCountrySpecific' { 'Home China'; break }
        '^Core' { 'Home'; break }
        '^ProfessionalWorkstation' { 'Pro for Workstations'; break }
        '^ProfessionalEducation' { 'Pro Education'; break }
        '^Professional' { 'Pro'; break }
        '^IoTEnterpriseS' { 'IoT Enterprise LTSC'; break }
        '^EnterpriseS' { 'Enterprise LTSC'; break }
        '^IoTEnterprise' { 'IoT Enterprise'; break }
        '^Enterprise' { 'Enterprise'; break }
        '^Education' { 'Education'; break }
        '^ServerRdsh' { 'Enterprise multi-session'; break }
        '^ServerStandard' { 'Standard'; break }
        '^ServerDatacenter' { 'Datacenter'; break }
        default { $EditionId }
    }

    if ($isServer -and $ProductName -like 'Windows Server*') {
        $name = $ProductName
    }
    else {
        $name = "$family $edition"
    }

    [pscustomobject]@{
        Name             = $name
        Family           = $family
        Edition          = $edition
        EditionId        = $EditionId
        DisplayVersion   = $DisplayVersion
        Build            = $Build
        Revision         = $Revision
        OsBuild          = '{0}.{1}' -f $Build, $Revision
        InstallationType = $InstallationType
        ServicingTrack   = $track
        IsServer         = $isServer
        IsLtsc           = $track -in @('LTSC', 'IoTLTSC')
        Architecture     = $Architecture
    }
}

function Get-WindowsVersionInfo {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

    $displayVersion = $cv.DisplayVersion          # 20H2 and later
    if (-not $displayVersion) { $displayVersion = $cv.ReleaseId }   # older Windows 10

    $architecture = $env:PROCESSOR_ARCHITEW6432   # set when running a 32-bit process
    if (-not $architecture) { $architecture = $env:PROCESSOR_ARCHITECTURE }

    ConvertTo-WindowsVersionInfo -Build ([int]$cv.CurrentBuild) -Revision ([int]$cv.UBR) `
        -DisplayVersion "$displayVersion" -EditionId "$($cv.EditionID)" `
        -InstallationType "$($cv.InstallationType)" -ProductName "$($cv.ProductName)" `
        -Architecture $architecture
}

function Get-WindowsLifecycleData {
    <#
        End-of-updates dates per build and servicing track.
        Sources (reviewed 2026-11-21):
          https://learn.microsoft.com/windows/release-health/windows11-release-information
          https://learn.microsoft.com/windows/release-health/release-information
          https://learn.microsoft.com/windows/release-health/windows-server-release-info
        Tracks:
          HomePro             Home, Pro, Pro Education, Pro for Workstations (24 months)
          EnterpriseEducation Enterprise, Education, IoT Enterprise (36 months)
          LTSC / IoTLTSC      Long-Term Servicing Channel
          Server              Windows Server (end of extended support)
        Windows 11 26H1 (build 28000) ships only on new devices.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    @'
Family,Build,Release,Track,EndOfUpdates
Windows 11,28000,26H1,HomePro,2028-03-14
Windows 11,28000,26H1,EnterpriseEducation,2029-03-13
Windows 11,26300,26H2,HomePro,2028-10-10
Windows 11,26300,26H2,EnterpriseEducation,2029-10-09
Windows 11,26200,25H2,HomePro,2027-10-12
Windows 11,26200,25H2,EnterpriseEducation,2028-10-10
Windows 11,26100,24H2,HomePro,2026-10-13
Windows 11,26100,24H2,EnterpriseEducation,2027-10-12
Windows 11,26100,LTSC 2024,LTSC,2029-10-09
Windows 11,26100,IoT LTSC 2024,IoTLTSC,2034-10-10
Windows 11,22631,23H2,HomePro,2025-11-11
Windows 11,22631,23H2,EnterpriseEducation,2026-11-10
Windows 11,22621,22H2,HomePro,2024-10-08
Windows 11,22621,22H2,EnterpriseEducation,2025-10-14
Windows 11,22000,21H2,HomePro,2023-10-10
Windows 11,22000,21H2,EnterpriseEducation,2024-10-08
Windows 10,19045,22H2,HomePro,2025-10-14
Windows 10,19045,22H2,EnterpriseEducation,2025-10-14
Windows 10,19044,21H2,HomePro,2023-06-13
Windows 10,19044,21H2,EnterpriseEducation,2024-06-11
Windows 10,19044,LTSC 2021,LTSC,2027-01-12
Windows 10,19044,IoT LTSC 2021,IoTLTSC,2032-01-13
Windows 10,17763,LTSC 2019,LTSC,2029-01-09
Windows 10,17763,IoT LTSC 2019,IoTLTSC,2029-01-09
Windows 10,14393,LTSB 2016,LTSC,2026-10-13
Windows 10,14393,IoT LTSB 2016,IoTLTSC,2026-10-13
Windows Server,26100,2025,Server,2034-11-14
Windows Server,20348,2022,Server,2031-10-14
Windows Server,17763,2019,Server,2029-01-09
Windows Server,14393,2016,Server,2027-01-12
'@ | ConvertFrom-Csv
}

function Get-WindowsLifecycleStatus {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $VersionInfo,

        [datetime] $AsOf = (Get-Date),

        [ValidateRange(1, 365)]
        [int] $WarningDays = 90
    )

    $entry = Get-WindowsLifecycleData | Where-Object {
        $_.Family -eq $VersionInfo.Family -and
        [int]$_.Build -eq $VersionInfo.Build -and
        $_.Track -eq $VersionInfo.ServicingTrack
    } | Select-Object -First 1

    if (-not $entry) {
        $isOldClientBuild = -not $VersionInfo.IsServer -and -not $VersionInfo.IsLtsc -and $VersionInfo.Build -lt 19045
        if ($isOldClientBuild) {
            return [pscustomobject]@{
                Status        = 'EndOfSupport'
                Release       = $VersionInfo.DisplayVersion
                EndOfUpdates  = $null
                DaysRemaining = $null
                Message       = "Build $($VersionInfo.Build) no longer receives updates. Upgrade to a supported Windows release."
            }
        }
        return [pscustomobject]@{
            Status        = 'Unknown'
            Release       = $VersionInfo.DisplayVersion
            EndOfUpdates  = $null
            DaysRemaining = $null
            Message       = "Build $($VersionInfo.Build) is not in the lifecycle table (Insider Preview, or newer than this script). See https://learn.microsoft.com/windows/release-health/"
        }
    }

    $end = [datetime]::ParseExact($entry.EndOfUpdates, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    $days = [int][math]::Floor(($end.Date - $AsOf.Date).TotalDays)

    if ($days -lt 0) {
        $status = 'EndOfSupport'
        $message = "No security updates since $($entry.EndOfUpdates)."
    }
    elseif ($days -le $WarningDays) {
        $status = 'EndingSoon'
        $message = "Security updates end on $($entry.EndOfUpdates) ($days days left)."
    }
    else {
        $status = 'Supported'
        $message = "Supported until $($entry.EndOfUpdates) ($days days left)."
    }

    if ($status -ne 'Supported') {
        if ($VersionInfo.Family -eq 'Windows 10' -and $VersionInfo.Build -eq 19045) {
            $message += ' Extended Security Updates (ESU) still apply if this device is enrolled; otherwise plan the move to Windows 11.'
        }
        elseif ($VersionInfo.Family -eq 'Windows 11' -and -not $VersionInfo.IsLtsc) {
            $message += ' Move to the latest version with -IncludeFeatureUpdates or Settings > Windows Update.'
        }
    }

    [pscustomobject]@{
        Status        = $status
        Release       = $entry.Release
        EndOfUpdates  = $entry.EndOfUpdates
        DaysRemaining = $days
        Message       = $message
    }
}

function Get-PendingRebootReason {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $reasons = @()
    if (Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $reasons += 'Component Based Servicing'
    }
    if (Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $reasons += 'Windows Update'
    }
    $sessionManager = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
    if ($sessionManager -and $sessionManager.PendingFileRenameOperations) {
        $reasons += 'Pending file rename operations'
    }
    $reasons
}

#endregion

#region Native command helpers -------------------------------------------------

function Invoke-NativeCommand {
    <#
        Runs a console program attached to the current console so its live progress
        (DISM, SFC, winget) is visible, and returns the exit code.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [string[]] $ArgumentList = @()
    )

    Write-MaintenanceLog ('> {0} {1}' -f (Split-Path -Path $FilePath -Leaf), ($ArgumentList -join ' ')) -Level Detail

    $startArgs = @{ FilePath = $FilePath; NoNewWindow = $true; Wait = $true; PassThru = $true }
    if ($ArgumentList.Count -gt 0) { $startArgs.ArgumentList = $ArgumentList }

    $process = Start-Process @startArgs
    [int]$process.ExitCode
}

function Get-WinGetPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $command = Get-Command -Name 'winget.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }

    # winget is not on PATH for SYSTEM or for an admin account that never signed in
    # interactively. Fall back to the App Installer package folder.
    $packageDirs = Get-ChildItem -Path (Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsApps') `
        -Filter 'Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe' -Directory -ErrorAction SilentlyContinue |
        Sort-Object -Descending -Property {
            $versionText = ($_.Name -split '_')[1]
            $parsed = $null
            if ([version]::TryParse($versionText, [ref]$parsed)) { $parsed } else { [version]'0.0' }
        }

    foreach ($dir in $packageDirs) {
        $candidate = Join-Path -Path $dir.FullName -ChildPath 'winget.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    $null
}

function Get-WinGetResult {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [int] $ExitCode
    )

    switch ($ExitCode) {
        0 { return (New-StepResult -Status Success -Message 'Applications are up to date.') }
        3010 { return (New-StepResult -Status Success -Message 'Applications upgraded; a restart is required to finish.' -RebootRequired) }
        -1978335212 { return (New-StepResult -Status Success -Message 'No installed applications matched (0x8A150014).') }
        -1978335189 { return (New-StepResult -Status Success -Message 'No applicable upgrades found (0x8A15002B).') }
        default {
            return (New-StepResult -Status Warning -Message ('winget exited with 0x{0:X8}; some applications may not have been upgraded. Run "winget upgrade" to review.' -f $ExitCode))
        }
    }
}

#endregion

#region Maintenance steps ------------------------------------------------------

function Get-LatestRestorePointSequence {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    try {
        $latest = Get-CimInstance -Namespace 'root/default' -ClassName 'SystemRestore' -ErrorAction Stop |
            Sort-Object -Property SequenceNumber -Descending | Select-Object -First 1
        if ($latest) { return [int]$latest.SequenceNumber }
    }
    catch {
        Write-MaintenanceLog "Restore points could not be listed: $($_.Exception.Message)" -Level Detail
    }
    0
}

function Invoke-RestorePointStep {
    [CmdletBinding()]
    param()

    # Checkpoint-Computer only exists in Windows PowerShell 5.1, so the WMI class is
    # used directly to support PowerShell 7 too.
    $before = Get-LatestRestorePointSequence
    $arguments = @{
        Description      = 'Windows Health and Update'
        RestorePointType = [uint32]12    # MODIFY_SETTINGS
        EventType        = [uint32]100   # BEGIN_SYSTEM_CHANGE
    }
    $result = Invoke-CimMethod -Namespace 'root/default' -ClassName 'SystemRestore' -MethodName 'CreateRestorePoint' -Arguments $arguments

    if ($result.ReturnValue -ne 0) {
        return (New-StepResult -Status Warning -Message ('Restore point not created (code {0}). System Protection may be off for {1}: enable it in System Properties > System Protection.' -f $result.ReturnValue, $env:SystemDrive))
    }

    $after = Get-LatestRestorePointSequence
    if ($after -gt $before) {
        return (New-StepResult -Status Success -Message "Restore point #$after created.")
    }
    New-StepResult -Status Success -Message 'Windows kept the restore point created in the last 24 hours (one per day is allowed by default).'
}

function Invoke-WinGetStep {
    [CmdletBinding()]
    param()

    $winget = Get-WinGetPath
    if (-not $winget) {
        return (New-StepResult -Status Skipped -Message 'winget not found. Install "App Installer" from the Microsoft Store or https://aka.ms/getwinget.')
    }

    $version = [version]'0.0'
    try {
        $rawVersion = & $winget --version 2>$null | Select-Object -First 1
        if ($LASTEXITCODE -eq 0 -and $rawVersion) {
            $versionText = $rawVersion -replace '^v', '' -replace '[^0-9.].*$', ''
            $null = [version]::TryParse($versionText, [ref]$version)
        }
    }
    catch {
        Write-MaintenanceLog "Could not read winget version: $($_.Exception.Message)" -Level Detail
    }
    Write-MaintenanceLog "winget $version at $winget" -Level Detail

    $sourceUpdateCode = Invoke-NativeCommand -FilePath $winget -ArgumentList @('source', 'update')
    if ($sourceUpdateCode -ne 0) {
        Write-MaintenanceLog ('winget source update exited with 0x{0:X8}; continuing with upgrade.' -f $sourceUpdateCode) -Level Warning
    }

    $upgradeArgs = @('upgrade', '--all', '--silent', '--accept-package-agreements', '--accept-source-agreements')
    if ($version -ge [version]'1.4') {
        $upgradeArgs += '--disable-interactivity'
    }
    else {
        Write-MaintenanceLog 'winget is older than 1.4: update "App Installer" for unattended upgrades.' -Level Warning
    }

    Get-WinGetResult -ExitCode (Invoke-NativeCommand -FilePath $winget -ArgumentList $upgradeArgs)
}

function Invoke-StoreUpdateStep {
    [CmdletBinding()]
    param()

    try {
        $appManagement = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01' -ErrorAction Stop
        $null = $appManagement | Invoke-CimMethod -MethodName 'UpdateScanMethod' -ErrorAction Stop
    }
    catch {
        return (New-StepResult -Status Warning -Message "Could not trigger the Store scan: $(Format-ErrorRecord -ErrorRecord $_)")
    }
    New-StepResult -Status Success -Message 'Store update scan triggered; app updates continue in the background.'
}

function Test-IsFeatureUpdate {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Update
    )

    # "Upgrades" category in Windows Update.
    $upgradesCategoryId = '3689bdc8-b205-4af4-8d4b-a63924c5e9d5'
    foreach ($category in $Update.Categories) {
        if ($category.CategoryID -eq $upgradesCategoryId) { return $true }
    }
    $false
}

function Invoke-WindowsUpdateStep {
    [CmdletBinding()]
    param(
        [switch] $IncludeDrivers,
        [switch] $IncludeFeatureUpdates
    )

    $session = New-Object -ComObject 'Microsoft.Update.Session'
    $session.ClientApplicationID = 'windows-health-and-update'

    $criteria = 'IsInstalled=0 and IsHidden=0'
    if (-not $IncludeDrivers) { $criteria += " and Type='Software'" }

    Write-MaintenanceLog "Searching Windows Update ($criteria)..."
    $search = $session.CreateUpdateSearcher().Search($criteria)

    $toInstall = New-Object -ComObject 'Microsoft.Update.UpdateColl'
    foreach ($update in $search.Updates) {
        if ($update.BrowseOnly) {
            Write-MaintenanceLog "Optional, not installed: $($update.Title)" -Level Detail
            continue
        }
        if (-not $IncludeFeatureUpdates -and (Test-IsFeatureUpdate -Update $update)) {
            Write-MaintenanceLog "Feature update, not installed (use -IncludeFeatureUpdates): $($update.Title)" -Level Warning
            continue
        }
        if ($update.InstallationBehavior.CanRequestUserInput) {
            Write-MaintenanceLog "Needs user input, install it from Settings: $($update.Title)" -Level Warning
            continue
        }
        if (-not $update.EulaAccepted) { $update.AcceptEula() }
        Write-MaintenanceLog "Queued: $($update.Title)"
        $null = $toInstall.Add($update)
    }

    if ($toInstall.Count -eq 0) {
        return (New-StepResult -Status Success -Message 'No pending updates.')
    }

    Write-MaintenanceLog "Downloading $($toInstall.Count) update(s)..."
    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $toInstall
    try {
        $null = $downloader.Download()
    }
    catch [System.Runtime.InteropServices.COMException] {
        if ($_.Exception.HResult -eq -2147024891) {
            return (New-StepResult -Status Failed -Message 'Windows Update download denied (0x80070005). The Windows Update Agent API blocks remote sessions (WinRM/SSH); run locally or via a scheduled task.')
        }
        throw
    }

    $downloaded = New-Object -ComObject 'Microsoft.Update.UpdateColl'
    foreach ($update in $toInstall) {
        if ($update.IsDownloaded) { $null = $downloaded.Add($update) }
        else { Write-MaintenanceLog "Download failed: $($update.Title)" -Level Warning }
    }
    $downloadFailed = $toInstall.Count - $downloaded.Count
    if ($downloaded.Count -eq 0) {
        return (New-StepResult -Status Failed -Message 'Updates were found but none could be downloaded. Check the network connection and try again.')
    }

    Write-MaintenanceLog "Installing $($downloaded.Count) update(s)..."
    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $downloaded
    try {
        $installResult = $installer.Install()
    }
    catch [System.Runtime.InteropServices.COMException] {
        if ($_.Exception.HResult -eq -2147024891) {
            return (New-StepResult -Status Failed -Message 'Windows Update install denied (0x80070005). The Windows Update Agent API blocks remote sessions (WinRM/SSH); run locally or via a scheduled task.')
        }
        throw
    }

    # OperationResultCode: 2 = Succeeded, 3 = SucceededWithErrors, 4 = Failed, 5 = Aborted
    $succeeded = 0
    $succeededWithErrors = 0
    $failed = 0
    for ($i = 0; $i -lt $downloaded.Count; $i++) {
        $title = $downloaded.Item($i).Title
        $code = $installResult.GetUpdateResult($i).ResultCode
        if ($code -eq 2) {
            $succeeded++
            Write-MaintenanceLog "Installed: $title" -Level Success
        }
        elseif ($code -eq 3) {
            $succeededWithErrors++
            Write-MaintenanceLog "Installed with errors: $title" -Level Warning
        }
        else {
            $failed++
            Write-MaintenanceLog "Failed (result code $code): $title" -Level Error
        }
    }

    $summaryParts = @("$succeeded installed")
    if ($succeededWithErrors -gt 0) { $summaryParts += "$succeededWithErrors installed with errors" }
    if ($downloadFailed -gt 0) { $summaryParts += "$downloadFailed download failed" }
    $summaryParts += "$failed failed"
    $summary = ($summaryParts -join ', ') + '.'

    $reboot = [bool]$installResult.RebootRequired
    if ($failed -gt 0 -and $succeeded -eq 0 -and $succeededWithErrors -eq 0) {
        return (New-StepResult -Status Failed -Message $summary -RebootRequired:$reboot)
    }
    if ($failed -gt 0 -or $downloadFailed -gt 0 -or $succeededWithErrors -gt 0) {
        return (New-StepResult -Status Warning -Message $summary -RebootRequired:$reboot)
    }
    New-StepResult -Status Success -Message $summary -RebootRequired:$reboot
}

function Invoke-DefenderStep {
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name 'Get-MpComputerStatus' -ErrorAction SilentlyContinue)) {
        return (New-StepResult -Status Skipped -Message 'Microsoft Defender module not available.')
    }

    try {
        $status = Get-MpComputerStatus -ErrorAction Stop
    }
    catch {
        return (New-StepResult -Status Skipped -Message 'Microsoft Defender is not running (another antivirus is probably active).')
    }

    $mode = $null
    if ($status.PSObject.Properties['AMRunningMode']) { $mode = $status.AMRunningMode }
    if (-not $status.AntivirusEnabled -or ($mode -and $mode -ne 'Normal')) {
        return (New-StepResult -Status Skipped -Message "Defender is not the primary antivirus (mode: $mode). Use your antivirus tools instead.")
    }

    Write-MaintenanceLog 'Updating Defender signatures...'
    try {
        Update-MpSignature -ErrorAction Stop
    }
    catch {
        Write-MaintenanceLog "Signature update failed: $(Format-ErrorRecord -ErrorRecord $_)" -Level Warning
    }

    Write-MaintenanceLog 'Running a quick scan...'
    Start-MpScan -ScanType QuickScan -ErrorAction Stop

    $status = Get-MpComputerStatus
    $activeThreats = @(Get-MpThreat -ErrorAction SilentlyContinue | Where-Object { $_.IsActive })
    $details = 'Signatures {0} ({1:yyyy-MM-dd}); quick scan completed.' -f $status.AntivirusSignatureVersion, $status.AntivirusSignatureLastUpdated

    if ($activeThreats.Count -gt 0) {
        return (New-StepResult -Status Warning -Message "$($activeThreats.Count) active threat(s): open Windows Security > Virus & threat protection. $details")
    }
    New-StepResult -Status Success -Message $details
}

function Invoke-RepairStep {
    [CmdletBinding()]
    param()

    $system = Get-NativeSystemPath
    $issues = @()
    $reboot = $false

    Write-MaintenanceLog 'DISM /RestoreHealth can take 10-30 minutes.'
    $dismCode = Invoke-NativeCommand -FilePath (Join-Path -Path $system -ChildPath 'dism.exe') -ArgumentList @('/Online', '/Cleanup-Image', '/RestoreHealth')
    switch ($dismCode) {
        0 { }
        3010 { $reboot = $true }
        default { $issues += ('DISM exit code 0x{0:X8} (see %windir%\Logs\DISM\dism.log)' -f $dismCode) }
    }

    $sfcCode = Invoke-NativeCommand -FilePath (Join-Path -Path $system -ChildPath 'sfc.exe') -ArgumentList @('/scannow')
    if ($sfcCode -ne 0) {
        $issues += "SFC exit code ${sfcCode}: verification failed or unrepairable integrity violations were found (see %windir%\Logs\CBS\CBS.log)"
    }

    if ($issues.Count -gt 0) {
        return (New-StepResult -Status Warning -Message ($issues -join '; ') -RebootRequired:$reboot)
    }
    New-StepResult -Status Success -Message 'Component store and system files are healthy.' -RebootRequired:$reboot
}

function Get-TempFolderPath {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $paths = @(Join-Path -Path $env:SystemRoot -ChildPath 'Temp')

    # Every local user profile, not only the account that elevated this session.
    $profiles = Get-CimInstance -ClassName 'Win32_UserProfile' -Filter 'Special = FALSE' -ErrorAction SilentlyContinue
    foreach ($userProfile in $profiles) {
        if (-not $userProfile.LocalPath) { continue }
        $temp = Join-Path -Path $userProfile.LocalPath -ChildPath 'AppData\Local\Temp'
        if (Test-Path -LiteralPath $temp -PathType Container -ErrorAction SilentlyContinue) { $paths += $temp }
    }
    $paths | Sort-Object -Unique
}

function Clear-StaleFile {
    <#
        Deletes files older than -OlderThan below -Path, then removes the folders that
        became empty. Skips reparse points (symlinks/junctions) so an elevated run
        cannot be tricked into deleting files outside -Path. Files in use are skipped
        and counted.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [datetime] $OlderThan
    )

    $freed = [long]0
    $inUse = 0
    $reparseFlag = [System.IO.FileAttributes]::ReparsePoint

    if (Test-Path -LiteralPath $Path -PathType Container -ErrorAction SilentlyContinue) {
        $rootAttributes = [System.IO.File]::GetAttributes($Path)
        if (($rootAttributes -band $reparseFlag) -eq 0) {
            $stack = New-Object -TypeName System.Collections.Generic.Stack[string]
            $visitedDirs = New-Object -TypeName System.Collections.Generic.List[object]
            $stack.Push($Path)

            while ($stack.Count -gt 0) {
                $currentDir = $stack.Pop()
                $children = Get-ChildItem -LiteralPath $currentDir -Force -ErrorAction SilentlyContinue
                foreach ($child in $children) {
                    if (($child.Attributes -band $reparseFlag) -ne 0) { continue }

                    if ($child.PSIsContainer) {
                        $stack.Push($child.FullName)
                        $visitedDirs.Add([pscustomobject]@{
                                FullName      = $child.FullName
                                LastWriteTime = $child.LastWriteTime
                            })
                    }
                    elseif ($child.LastWriteTime -lt $OlderThan) {
                        try {
                            $size = $child.Length
                            Remove-Item -LiteralPath $child.FullName -Force -ErrorAction Stop
                            $freed += $size
                        }
                        catch {
                            $inUse++
                        }
                    }
                }
            }

            $visitedDirs |
                Where-Object { $_.LastWriteTime -lt $OlderThan } |
                Sort-Object -Property { $_.FullName.Length } -Descending |
                ForEach-Object {
                    try {
                        if (([System.IO.File]::GetAttributes($_.FullName) -band $reparseFlag) -ne 0) { return }
                        if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                        }
                    }
                    catch {
                        Write-MaintenanceLog "Could not remove empty directory $($_.FullName): $($_.Exception.Message)" -Level Detail
                    }
                }
        }
    }

    [pscustomobject]@{ Path = $Path; BytesFreed = $freed; FilesInUse = $inUse }
}

function Invoke-CleanupStep {
    [CmdletBinding()]
    param(
        [int] $TempFileAgeDays = 2
    )

    $notes = @()
    $warnings = @()
    $reboot = $false

    # /ResetBase is deliberately not used: it would make installed updates impossible to uninstall.
    $dism = Join-Path -Path (Get-NativeSystemPath) -ChildPath 'dism.exe'
    $dismCode = Invoke-NativeCommand -FilePath $dism -ArgumentList @('/Online', '/Cleanup-Image', '/StartComponentCleanup')
    switch ($dismCode) {
        0 { $notes += 'component store cleaned' }
        3010 { $notes += 'component store cleaned (restart required)'; $reboot = $true }
        default { $warnings += ('component cleanup exit code 0x{0:X8}' -f $dismCode) }
    }

    $cutoff = (Get-Date).AddDays(-$TempFileAgeDays)
    $totalFreed = [long]0
    $totalInUse = 0
    foreach ($path in Get-TempFolderPath) {
        $result = Clear-StaleFile -Path $path -OlderThan $cutoff
        Write-MaintenanceLog ('{0}: {1:N1} MB freed' -f $path, ($result.BytesFreed / 1MB)) -Level Detail
        $totalFreed += $result.BytesFreed
        $totalInUse += $result.FilesInUse
    }
    $notes += ('{0:N1} MB of temp files removed ({1} in use, kept)' -f ($totalFreed / 1MB), $totalInUse)

    # Delivery Optimization cmdlets exist on Windows 10 1809+ / Windows 11.
    if (Get-Command -Name 'Delete-DeliveryOptimizationCache' -ErrorAction SilentlyContinue) {
        try {
            Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
            $notes += 'Delivery Optimization cache cleared'
        }
        catch {
            $warnings += "Delivery Optimization: $(Format-ErrorRecord -ErrorRecord $_)"
        }
    }

    $message = ($notes + $warnings) -join '; '
    if ($warnings.Count -gt 0) {
        return (New-StepResult -Status Warning -Message $message -RebootRequired:$reboot)
    }
    New-StepResult -Status Success -Message $message -RebootRequired:$reboot
}

function Invoke-DiskHealthStep {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 99)]
        [int] $MinFreePercent = 10
    )

    $issues = @()

    $disks = @(Get-PhysicalDisk | Sort-Object -Property DeviceId)
    $diskRows = foreach ($disk in $disks) {
        $counters = $null
        try {
            $counters = $disk | Get-StorageReliabilityCounter -ErrorAction Stop
        }
        catch {
            Write-MaintenanceLog "Reliability counters unavailable for $($disk.FriendlyName)." -Level Detail
        }

        if ($disk.HealthStatus -ne 'Healthy') {
            $issues += "disk '$($disk.FriendlyName)' is $($disk.HealthStatus)"
        }
        if ($counters -and $counters.Wear -ge 90) {
            $issues += "disk '$($disk.FriendlyName)' wear at $($counters.Wear)%"
        }
        if ($counters -and $counters.ReadErrorsUncorrected -gt 0) {
            $issues += "disk '$($disk.FriendlyName)' has $($counters.ReadErrorsUncorrected) uncorrected read errors"
        }

        $temperature = '-'
        $wear = '-'
        if ($counters -and $counters.Temperature) { $temperature = $counters.Temperature }
        if ($counters -and $null -ne $counters.Wear) { $wear = $counters.Wear }

        [pscustomobject]@{
            Disk       = $disk.FriendlyName
            Media      = $disk.MediaType
            Bus        = $disk.BusType
            'Size(GB)' = [math]::Round($disk.Size / 1GB)
            Health     = $disk.HealthStatus
            'Temp(C)'  = $temperature
            'Wear(%)'  = $wear
        }
    }
    $diskRows | Format-Table -AutoSize | Out-Host

    $volumes = @(Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size -gt 0 } | Sort-Object -Property DriveLetter)
    $volumeRows = foreach ($volume in $volumes) {
        $freePercent = [math]::Round(($volume.SizeRemaining / $volume.Size) * 100, 1)
        if ($freePercent -lt $MinFreePercent) {
            $issues += "drive $($volume.DriveLetter): only $freePercent% free"
        }
        [pscustomobject]@{
            Drive       = "$($volume.DriveLetter):"
            Label       = $volume.FileSystemLabel
            FileSystem  = $volume.FileSystem
            'Free(GB)'  = [math]::Round($volume.SizeRemaining / 1GB, 1)
            'Total(GB)' = [math]::Round($volume.Size / 1GB, 1)
            'Free(%)'   = $freePercent
            Health      = $volume.HealthStatus
        }
    }
    $volumeRows | Format-Table -AutoSize | Out-Host

    if ($issues.Count -gt 0) {
        return (New-StepResult -Status Warning -Message ($issues -join '; '))
    }
    New-StepResult -Status Success -Message "$($disks.Count) disk(s) healthy; $($volumes.Count) volume(s) above $MinFreePercent% free."
}

function Invoke-UpgradeReadinessStep {
    <#
        Windows 10 reached end of support on 2025-10-14. This checks the requirements
        that can be verified locally; the CPU model list is not checked (use PC Health Check).
    #>
    [CmdletBinding()]
    param()

    $checks = @()

    $tpm = $null
    try {
        $tpm = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName 'Win32_Tpm' -ErrorAction Stop
    }
    catch {
        Write-MaintenanceLog 'TPM information unavailable.' -Level Detail
    }
    $tpmVersion = $null
    if ($tpm -and $tpm.SpecVersion) { $tpmVersion = ($tpm.SpecVersion -split ',')[0].Trim() }
    $parsedTpmVersion = $null
    $tpmOk = $tpmVersion -and [version]::TryParse($tpmVersion, [ref]$parsedTpmVersion) -and ($parsedTpmVersion -ge [version]'2.0')
    $checks += [pscustomobject]@{ Requirement = 'TPM 2.0'; Found = $(if ($tpmVersion) { "TPM $tpmVersion" } else { 'not found' }); Pass = [bool]$tpmOk }

    # The SecureBoot\State key only exists on UEFI systems.
    $secureBootState = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -Name 'UEFISecureBootEnabled' -ErrorAction SilentlyContinue
    if ($null -eq $secureBootState) {
        $checks += [pscustomobject]@{ Requirement = 'UEFI + Secure Boot'; Found = 'legacy BIOS'; Pass = $false }
    }
    else {
        $enabled = $secureBootState.UEFISecureBootEnabled -eq 1
        $checks += [pscustomobject]@{ Requirement = 'UEFI + Secure Boot'; Found = $(if ($enabled) { 'enabled' } else { 'UEFI, Secure Boot off' }); Pass = $enabled }
    }

    # Win32_PhysicalMemory can be empty on VMs (e.g. Hyper-V dynamic memory); fall back to Win32_ComputerSystem.
    $totalMemoryBytes = (Get-CimInstance -ClassName 'Win32_PhysicalMemory' -ErrorAction SilentlyContinue | Measure-Object -Property Capacity -Sum).Sum
    if (-not $totalMemoryBytes) {
        $computerSystem = Get-CimInstance -ClassName 'Win32_ComputerSystem' -ErrorAction SilentlyContinue
        if ($computerSystem) { $totalMemoryBytes = $computerSystem.TotalPhysicalMemory }
    }
    $memoryGB = if ($totalMemoryBytes) { [math]::Round($totalMemoryBytes / 1GB, 1) } else { 0 }
    $checks += [pscustomobject]@{ Requirement = 'RAM >= 4 GB'; Found = "$memoryGB GB"; Pass = $memoryGB -ge 4 }

    $systemDisk = Get-Partition -DriveLetter $env:SystemDrive.TrimEnd(':') -ErrorAction SilentlyContinue | Get-Disk -ErrorAction SilentlyContinue
    if ($systemDisk) {
        $diskGB = [math]::Round($systemDisk.Size / 1e9)
        $checks += [pscustomobject]@{ Requirement = 'Storage >= 64 GB'; Found = "$diskGB GB"; Pass = $systemDisk.Size -ge 64e9 }
    }

    $cpus = @(Get-CimInstance -ClassName 'Win32_Processor' -ErrorAction SilentlyContinue)
    $cpu = $cpus | Select-Object -First 1
    if ($cpu) {
        $totalCores = ($cpus | Measure-Object -Property NumberOfCores -Sum).Sum
        $cpuName = if ($cpu.Name) { $cpu.Name.Trim() } else { 'Unknown CPU' }
        $cpuOk = $cpu.AddressWidth -eq 64 -and $totalCores -ge 2 -and $cpu.MaxClockSpeed -ge 1000
        $checks += [pscustomobject]@{ Requirement = '64-bit CPU, 2+ cores, 1 GHz+'; Found = "$cpuName ($totalCores cores)"; Pass = [bool]$cpuOk }
    }
    else {
        $checks += [pscustomobject]@{ Requirement = '64-bit CPU, 2+ cores, 1 GHz+'; Found = 'unavailable'; Pass = $false }
    }

    $checks | Format-Table -AutoSize | Out-Host

    $failed = @($checks | Where-Object { -not $_.Pass })
    $cpuNote = 'CPU model support not verified: confirm with PC Health Check (https://aka.ms/GetPCHealthCheckApp).'
    if ($failed.Count -gt 0) {
        return (New-StepResult -Status Warning -Message ("Not ready for Windows 11: {0}. {1}" -f (($failed.Requirement) -join ', '), $cpuNote))
    }
    New-StepResult -Status Success -Message "Meets the checked Windows 11 requirements. $cpuNote"
}

#endregion

#region Orchestration ----------------------------------------------------------

function Invoke-MaintenanceStep {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock] $Action
    )

    # Any unhandled error inside a step becomes a "Failed" result instead of
    # stopping the whole maintenance run.
    $ErrorActionPreference = 'Stop'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $result = & $Action |
            Where-Object { $null -ne $_ -and $_.PSObject.TypeNames -contains 'WindowsMaintenance.StepResult' } |
            Select-Object -Last 1
        if (-not $result) { $result = New-StepResult -Status Success -Message 'Completed.' }
    }
    catch {
        $result = New-StepResult -Status Failed -Message (Format-ErrorRecord -ErrorRecord $_)
    }
    $stopwatch.Stop()
    $result.Duration = $stopwatch.Elapsed
    $result
}

function Clear-OldLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Directory,

        [Parameter(Mandatory = $true)]
        [int] $RetentionDays
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container -ErrorAction SilentlyContinue)) { return }
    $reparseFlag = [System.IO.FileAttributes]::ReparsePoint
    if (([System.IO.File]::GetAttributes($Directory) -band $reparseFlag) -ne 0) { return }

    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    Get-ChildItem -LiteralPath $Directory -File -Filter 'maintenance_*' -ErrorAction SilentlyContinue |
        Where-Object {
            (($_.Attributes -band $reparseFlag) -eq 0) -and
            ($_.LastWriteTime -lt $cutoff)
        } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

#endregion

# ---- Entry point -------------------------------------------------------------
# When dot-sourced (for example by the Pester tests) only the functions are loaded.
if ($MyInvocation.InvocationName -eq '.') { return }

if (-not (Test-IsAdministrator)) {
    Write-MaintenanceLog 'Run this script from an elevated PowerShell (right-click > Run as administrator).' -Level Error
    exit 1
}

$null = New-Item -Path $LogDirectory -ItemType Directory -Force -WhatIf:$false -Confirm:$false
$startedAt = Get-Date
$timestamp = $startedAt.ToString('yyyyMMdd_HHmmss')
$transcriptPath = Join-Path -Path $LogDirectory -ChildPath "maintenance_$timestamp.log"
$reportPath = Join-Path -Path $LogDirectory -ChildPath "maintenance_$timestamp.json"
$results = New-Object -TypeName System.Collections.Generic.List[object]
$rebootReasons = New-Object -TypeName System.Collections.Generic.List[string]
$transcriptStarted = $false
$exitCode = 0

try {
    try {
        $null = Start-Transcript -Path $transcriptPath -WhatIf:$false -Confirm:$false
        $transcriptStarted = $true
    }
    catch {
        Write-MaintenanceLog "Transcript not started: $($_.Exception.Message)" -Level Warning
    }

    if (-not $WhatIfPreference) {
        Clear-OldLog -Directory $LogDirectory -RetentionDays $LogRetentionDays
    }

    $os = Get-WindowsVersionInfo
    $lifecycle = Get-WindowsLifecycleStatus -VersionInfo $os

    Write-MaintenanceLog "Windows Health & Update v$ScriptVersion" -Level Header
    Write-MaintenanceLog ('System     : {0}, version {1} (OS build {2}, {3})' -f $os.Name, $lifecycle.Release, $os.OsBuild, $os.Architecture)
    $supportLevel = @{ Supported = 'Success'; EndingSoon = 'Warning'; EndOfSupport = 'Error'; Unknown = 'Warning' }[$lifecycle.Status]
    Write-MaintenanceLog ('Support    : {0}' -f $lifecycle.Message) -Level $supportLevel
    Write-MaintenanceLog ('PowerShell : {0} ({1}-bit)' -f $PSVersionTable.PSVersion, $(if ([Environment]::Is64BitProcess) { 64 } else { 32 }))
    Write-MaintenanceLog ('Logs       : {0}' -f $LogDirectory)

    $pendingBefore = @(Get-PendingRebootReason)
    if ($pendingBefore.Count -gt 0) {
        Write-MaintenanceLog ('A restart was already pending ({0}). Some updates and repairs may only finish after restarting.' -f ($pendingBefore -join ', ')) -Level Warning
    }

    # Each step can declare why it does not apply to the detected Windows release.
    $steps = @(
        @{
            Name          = 'RestorePoint'
            Title         = 'Create a System Restore point'
            NotApplicable = $(if ($os.IsServer) { 'System Restore does not exist on Windows Server.' })
            Action        = { Invoke-RestorePointStep }
        }
        @{
            Name   = 'WinGet'
            Title  = 'Update applications (winget)'
            Action = { Invoke-WinGetStep }
        }
        @{
            Name          = 'Store'
            Title         = 'Update Microsoft Store apps'
            NotApplicable = $(if ($os.IsServer -or $os.IsLtsc) { "Microsoft Store is not part of $($os.Name)." })
            Action        = { Invoke-StoreUpdateStep }
        }
        @{
            Name   = 'WindowsUpdate'
            Title  = 'Install Windows updates'
            Action = { Invoke-WindowsUpdateStep -IncludeDrivers:$IncludeDrivers -IncludeFeatureUpdates:$IncludeFeatureUpdates }
        }
        @{
            Name   = 'Defender'
            Title  = 'Update Microsoft Defender and run a quick scan'
            Action = { Invoke-DefenderStep }
        }
        @{
            Name   = 'Repair'
            Title  = 'Repair Windows image and system files (DISM + SFC)'
            Action = { Invoke-RepairStep }
        }
        @{
            Name   = 'Cleanup'
            Title  = 'Clean up components and temporary files'
            Action = { Invoke-CleanupStep -TempFileAgeDays $TempFileAgeDays }
        }
        @{
            Name   = 'DiskHealth'
            Title  = 'Check disk health and free space'
            Action = { Invoke-DiskHealthStep }
        }
        @{
            Name          = 'UpgradeReadiness'
            Title         = 'Check Windows 11 upgrade readiness'
            NotApplicable = $(if ($os.Family -ne 'Windows 10' -or $os.IsLtsc) { 'Only relevant on Windows 10 (non-LTSC).' })
            Action        = { Invoke-UpgradeReadinessStep }
        }
    )

    $index = 0
    foreach ($step in $steps) {
        $index++
        $skipReason = $null
        if ($Only.Count -gt 0 -and $step.Name -notin $Only) { $skipReason = 'Not selected with -Only.' }
        elseif ($step.Name -in $Skip) { $skipReason = 'Skipped with -Skip.' }
        elseif ($step.NotApplicable) { $skipReason = "Not applicable: $($step.NotApplicable)" }

        Write-MaintenanceLog ('[{0}/{1}] {2}' -f $index, $steps.Count, $step.Title) -Level Header

        if (-not $skipReason -and -not $PSCmdlet.ShouldProcess($step.Title)) {
            $skipReason = 'Not run (-WhatIf or declined).'
        }

        if ($skipReason) {
            $result = New-StepResult -Status Skipped -Message $skipReason
        }
        else {
            $result = Invoke-MaintenanceStep -Action $step.Action
        }

        if ($result.RebootRequired -and -not $rebootReasons.Contains($step.Name)) { $rebootReasons.Add($step.Name) }

        $level = @{ Success = 'Success'; Warning = 'Warning'; Failed = 'Error'; Skipped = 'Detail' }[$result.Status]
        Write-MaintenanceLog $result.Message -Level $level

        $results.Add([pscustomobject]@{
                Step     = $step.Name
                Status   = $result.Status
                Duration = $result.Duration.ToString('hh\:mm\:ss')
                Message  = $result.Message
            })
    }

    foreach ($reason in Get-PendingRebootReason) {
        if (-not $rebootReasons.Contains($reason)) { $rebootReasons.Add($reason) }
    }
    $rebootRequired = $rebootReasons.Count -gt 0

    Write-MaintenanceLog 'Summary' -Level Header
    foreach ($row in $results) {
        $level = @{ Success = 'Success'; Warning = 'Warning'; Failed = 'Error'; Skipped = 'Detail' }[$row.Status]
        Write-MaintenanceLog ('{0,-17} {1,-8} {2}  {3}' -f $row.Step, $row.Status, $row.Duration, $row.Message) -Level $level
    }

    if (@($results | Where-Object { $_.Status -eq 'Failed' }).Count -gt 0) {
        $exitCode = 1
    }
    elseif ($rebootRequired) {
        $exitCode = 3010
    }

    $report = [ordered]@{
        scriptVersion  = $ScriptVersion
        startedAt      = $startedAt.ToString('o')
        finishedAt     = (Get-Date).ToString('o')
        os             = $os
        lifecycle      = $lifecycle
        parameters     = [ordered]@{
            skip                  = $Skip
            only                  = $Only
            includeDrivers        = [bool]$IncludeDrivers
            includeFeatureUpdates = [bool]$IncludeFeatureUpdates
            autoReboot            = [bool]$AutoReboot
            tempFileAgeDays       = $TempFileAgeDays
            logRetentionDays      = $LogRetentionDays
            whatIf                = [bool]$WhatIfPreference
        }
        steps          = $results
        rebootRequired = $rebootRequired
        rebootReasons  = $rebootReasons
        exitCode       = $exitCode
    }
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8 -WhatIf:$false -Confirm:$false
    Write-MaintenanceLog "Report: $reportPath" -Level Detail

    if ($rebootRequired) {
        if ($AutoReboot -and $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Restart in 2 minutes')) {
            Write-MaintenanceLog 'Restarting in 2 minutes. Cancel with: shutdown /a' -Level Warning
            & (Join-Path -Path (Get-NativeSystemPath) -ChildPath 'shutdown.exe') /r /t 120 /c 'Windows Health & Update: restarting to finish updates.'
        }
        else {
            Write-MaintenanceLog ('Restart required to finish: {0}.' -f ($rebootReasons -join ', ')) -Level Warning
        }
    }
}
catch {
    Write-MaintenanceLog "Unexpected error: $(Format-ErrorRecord -ErrorRecord $_)" -Level Error
    $exitCode = 1
}
finally {
    if ($transcriptStarted) { $null = Stop-Transcript }
}

exit $exitCode
