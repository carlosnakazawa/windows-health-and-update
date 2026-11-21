<#
.SYNOPSIS
    Registers (or removes) a scheduled task that runs Invoke-WindowsMaintenance.ps1.

.DESCRIPTION
    Creates a Task Scheduler task that runs the maintenance script as the current user
    with highest privileges, only while that user is signed in, so no password is stored
    and winget works with the user's packages.

    The task starts as soon as possible when the scheduled time was missed (for example,
    the PC was off), requires a network connection, never starts a second instance and
    is stopped after 4 hours.

    Security: the task runs the script elevated. Keep the script in a folder that standard
    users cannot modify, such as C:\Program Files\WindowsHealthAndUpdate, otherwise any
    process running as your user could change the script and gain administrator rights.

.PARAMETER Frequency
    Daily or Weekly. Default: Weekly.

.PARAMETER DayOfWeek
    Day for the weekly schedule. Default: Sunday.

.PARAMETER At
    Start time in 24-hour HH:mm format. Default: 10:00.

.PARAMETER ScriptPath
    Path to Invoke-WindowsMaintenance.ps1. Default: the copy next to this script.

.PARAMETER MaintenanceArguments
    Extra arguments passed to the maintenance script, for example '-Skip Repair'.

.PARAMETER TaskName
    Name of the scheduled task. Default: 'Windows Health and Update'.

.PARAMETER Unregister
    Removes the scheduled task.

.EXAMPLE
    .\Register-MaintenanceTask.ps1

    Runs the maintenance every Sunday at 10:00.

.EXAMPLE
    .\Register-MaintenanceTask.ps1 -Frequency Daily -At 12:30 -MaintenanceArguments '-Only WinGet, WindowsUpdate'

    Updates applications and Windows every day at 12:30.

.EXAMPLE
    .\Register-MaintenanceTask.ps1 -Unregister

    Removes the task.

.LINK
    https://github.com/carlosnakazawa/windows-health-and-update
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Register')]
param(
    [Parameter(ParameterSetName = 'Register')]
    [ValidateSet('Daily', 'Weekly')]
    [string] $Frequency = 'Weekly',

    [Parameter(ParameterSetName = 'Register')]
    [System.DayOfWeek] $DayOfWeek = [System.DayOfWeek]::Sunday,

    [Parameter(ParameterSetName = 'Register')]
    [ValidatePattern('^([01]\d|2[0-3]):[0-5]\d$')]
    [string] $At = '10:00',

    [Parameter(ParameterSetName = 'Register')]
    [string] $ScriptPath = (Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-WindowsMaintenance.ps1'),

    [Parameter(ParameterSetName = 'Register')]
    [string] $MaintenanceArguments = '',

    [ValidateNotNullOrEmpty()]
    [string] $TaskName = 'Windows Health and Update',

    [Parameter(Mandatory = $true, ParameterSetName = 'Unregister')]
    [switch] $Unregister
)

$ErrorActionPreference = 'Stop'

$principalCheck = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principalCheck.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell (Run as administrator).'
}

if ($Unregister) {
    if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
        Write-Output "Task '$TaskName' does not exist."
        return
    }
    if ($PSCmdlet.ShouldProcess($TaskName, 'Unregister scheduled task')) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Output "Task '$TaskName' removed."
    }
    return
}

$resolvedScript = (Resolve-Path -LiteralPath $ScriptPath).ProviderPath
if ($resolvedScript -like "$env:USERPROFILE\*") {
    Write-Warning ("The script is inside your user profile ({0}). Because the task runs elevated, move it to a folder only administrators can modify, e.g. C:\Program Files\WindowsHealthAndUpdate." -f $resolvedScript)
}

$powershell = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File "{0}" {1}' -f $resolvedScript, $MaintenanceArguments).Trim()

$startTime = [datetime]::ParseExact($At, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture)
if ($Frequency -eq 'Daily') {
    $trigger = New-ScheduledTaskTrigger -Daily -At $startTime
    $scheduleText = "daily at $At"
}
else {
    $trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek $DayOfWeek -At $startTime
    $scheduleText = "every $DayOfWeek at $At"
}

$action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments
$userId = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 4) -MultipleInstances IgnoreNew

if ($PSCmdlet.ShouldProcess($TaskName, "Register scheduled task ($scheduleText)")) {
    $null = Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
        -Description 'Windows Health & Update: apps, Windows Update, Defender, DISM/SFC, cleanup and disk health. https://github.com/carlosnakazawa/windows-health-and-update' -Force
    Write-Output "Task '$TaskName' registered: runs $scheduleText as $userId."
    Write-Output "Run it now with: Start-ScheduledTask -TaskName '$TaskName'"
}
