#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares variables from BeforeDiscovery/BeforeAll with It blocks.')]
param()

BeforeAll {
    # Not named $scriptPath: dot-sourcing Register-MaintenanceTask.ps1 would overwrite it
    # with its own -ScriptPath parameter (PowerShell variable names are case-insensitive).
    $mainScriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Invoke-WindowsMaintenance.ps1'
    $schedulerPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Register-MaintenanceTask.ps1'
    # Dot-sourcing loads the functions only; the entry points return early.
    . $mainScriptPath
    . $schedulerPath

    function Get-TestVersionInfo {
        param([int] $Build, [string] $EditionId, [string] $InstallationType = 'Client', [string] $ProductName = '')
        ConvertTo-WindowsVersionInfo -Build $Build -EditionId $EditionId -InstallationType $InstallationType -ProductName $ProductName
    }

    # Lifecycle checks use a fixed reference date so the tests do not expire.
    function Get-TestLifecycleStatus {
        param([int] $Build, [string] $EditionId, [string] $InstallationType = 'Client', [datetime] $AsOf = '2026-11-21')
        $info = Get-TestVersionInfo -Build $Build -EditionId $EditionId -InstallationType $InstallationType
        Get-WindowsLifecycleStatus -VersionInfo $info -AsOf $AsOf
    }
}

Describe 'Script files' {
    It '<Name> has no syntax errors' -ForEach @(
        @{ Name = 'Invoke-WindowsMaintenance.ps1' }
        @{ Name = 'Register-MaintenanceTask.ps1' }
        @{ Name = 'scripts\Invoke-HarnessCheck.ps1' }
    ) {
        $path = Join-Path -Path $PSScriptRoot -ChildPath "..\$Name"
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It '<Name> is ASCII-only (Windows PowerShell 5.1 reads BOM-less files as ANSI)' -ForEach @(
        @{ Name = 'Invoke-WindowsMaintenance.ps1' }
        @{ Name = 'Register-MaintenanceTask.ps1' }
        @{ Name = 'scripts\Invoke-HarnessCheck.ps1' }
    ) {
        $path = Join-Path -Path $PSScriptRoot -ChildPath "..\$Name"
        $nonAscii = [System.IO.File]::ReadAllBytes($path) | Where-Object { $_ -gt 127 }
        $nonAscii | Should -BeNullOrEmpty
    }
}

Describe 'Documentation' {
    BeforeDiscovery {
        $repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath
        $readmeFiles = @(Get-Item -LiteralPath (Join-Path $repoRoot 'README.md')) +
            @(Get-ChildItem -Path (Join-Path $repoRoot 'docs') -Filter 'README.*.md')
        $markdownFiles = $readmeFiles + @(
            Get-Item -LiteralPath (Join-Path $repoRoot 'CONTRIBUTING.md')
            Get-Item -LiteralPath (Join-Path $repoRoot 'SECURITY.md')
            Get-Item -LiteralPath (Join-Path $repoRoot 'AGENTS.md')
            Get-Item -LiteralPath (Join-Path $repoRoot 'CLAUDE.md')
        )
        $readmeCases = $readmeFiles | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
        $markdownCases = $markdownFiles | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
    }

    BeforeAll {
        $repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath
        $allReadmes = @(Join-Path $repoRoot 'README.md') +
            @(Get-ChildItem -Path (Join-Path $repoRoot 'docs') -Filter 'README.*.md' | ForEach-Object { $_.FullName })

        function Get-RelativeLinkTarget {
            param([string] $Path)
            $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
            $directory = Split-Path -Path $Path -Parent
            foreach ($match in [regex]::Matches($text, '\]\(([^)\s#]+)(#[^)]*)?\)')) {
                $link = $match.Groups[1].Value
                if ($link -match '^(https?|mailto):') { continue }
                [System.IO.Path]::GetFullPath((Join-Path -Path $directory -ChildPath $link))
            }
        }
    }

    It '<Name> has no broken relative links' -ForEach $markdownCases {
        $missing = Get-RelativeLinkTarget -Path $Path | Where-Object { -not (Test-Path -LiteralPath $_) }
        $missing | Should -BeNullOrEmpty
    }

    It '<Name> links to every other language' -ForEach $readmeCases {
        $targets = @(Get-RelativeLinkTarget -Path $Path) + $Path
        $notLinked = $allReadmes | Where-Object { $targets -notcontains $_ }
        $notLinked | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-WindowsVersionInfo' {
    It 'reports Windows 11 even though the registry ProductName says Windows 10' {
        $info = ConvertTo-WindowsVersionInfo -Build 26300 -EditionId 'CoreSingleLanguage' -ProductName 'Windows 10 Home Single Language'
        $info.Family | Should -Be 'Windows 11'
        $info.Name | Should -Be 'Windows 11 Home Single Language'
        $info.ServicingTrack | Should -Be 'HomePro'
        $info.IsLtsc | Should -BeFalse
    }

    It 'maps <EditionId> on build <Build> to <Family> / <Track>' -ForEach @(
        @{ Build = 19045; EditionId = 'Professional'; Family = 'Windows 10'; Track = 'HomePro'; Edition = 'Pro' }
        @{ Build = 22631; EditionId = 'ProfessionalWorkstation'; Family = 'Windows 11'; Track = 'HomePro'; Edition = 'Pro for Workstations' }
        @{ Build = 26100; EditionId = 'Enterprise'; Family = 'Windows 11'; Track = 'EnterpriseEducation'; Edition = 'Enterprise' }
        @{ Build = 26200; EditionId = 'Education'; Family = 'Windows 11'; Track = 'EnterpriseEducation'; Edition = 'Education' }
        @{ Build = 26100; EditionId = 'IoTEnterprise'; Family = 'Windows 11'; Track = 'EnterpriseEducation'; Edition = 'IoT Enterprise' }
        @{ Build = 19044; EditionId = 'EnterpriseS'; Family = 'Windows 10'; Track = 'LTSC'; Edition = 'Enterprise LTSC' }
        @{ Build = 26100; EditionId = 'IoTEnterpriseS'; Family = 'Windows 11'; Track = 'IoTLTSC'; Edition = 'IoT Enterprise LTSC' }
    ) {
        $info = Get-TestVersionInfo -Build $Build -EditionId $EditionId
        $info.Family | Should -Be $Family
        $info.ServicingTrack | Should -Be $Track
        $info.Edition | Should -Be $Edition
    }

    It 'detects Windows Server, including Server Core' {
        $info = Get-TestVersionInfo -Build 20348 -EditionId 'ServerDatacenter' -InstallationType 'Server Core' -ProductName 'Windows Server 2022 Datacenter'
        $info.IsServer | Should -BeTrue
        $info.Family | Should -Be 'Windows Server'
        $info.Name | Should -Be 'Windows Server 2022 Datacenter'
        $info.ServicingTrack | Should -Be 'Server'
    }

    It 'flags LTSC editions' {
        (Get-TestVersionInfo -Build 19044 -EditionId 'EnterpriseS').IsLtsc | Should -BeTrue
        (Get-TestVersionInfo -Build 19044 -EditionId 'EnterpriseN').IsLtsc | Should -BeFalse
    }
}

Describe 'Get-WindowsLifecycleData' {
    It 'has unique Family/Build/Track rows' {
        $keys = Get-WindowsLifecycleData | ForEach-Object { '{0}|{1}|{2}' -f $_.Family, $_.Build, $_.Track }
        ($keys | Sort-Object -Unique).Count | Should -Be $keys.Count
    }

    It 'uses ISO dates only' {
        Get-WindowsLifecycleData | ForEach-Object { $_.EndOfUpdates | Should -Match '^\d{4}-\d{2}-\d{2}$' }
    }
}

Describe 'Get-WindowsLifecycleStatus' {
    It '<Description>' -ForEach @(
        @{ Description = 'Windows 11 26H2 Home is supported'; Build = 26300; EditionId = 'Core'; ExpectedStatus = 'Supported'; Release = '26H2' }
        @{ Description = 'Windows 11 24H2 Pro is out of support'; Build = 26100; EditionId = 'Professional'; ExpectedStatus = 'EndOfSupport'; Release = '24H2' }
        @{ Description = 'Windows 11 24H2 Enterprise is still supported'; Build = 26100; EditionId = 'Enterprise'; ExpectedStatus = 'Supported'; Release = '24H2' }
        @{ Description = 'Windows 11 LTSC 2024 is supported'; Build = 26100; EditionId = 'EnterpriseS'; ExpectedStatus = 'Supported'; Release = 'LTSC 2024' }
        @{ Description = 'Windows 10 22H2 is out of support'; Build = 19045; EditionId = 'Professional'; ExpectedStatus = 'EndOfSupport'; Release = '22H2' }
        @{ Description = 'Windows 10 LTSC 2021 is ending soon'; Build = 19044; EditionId = 'EnterpriseS'; ExpectedStatus = 'EndingSoon'; Release = 'LTSC 2021' }
        @{ Description = 'Windows 10 LTSC 2019 is supported'; Build = 17763; EditionId = 'EnterpriseS'; ExpectedStatus = 'Supported'; Release = 'LTSC 2019' }
    ) {
        $lifecycle = Get-TestLifecycleStatus -Build $Build -EditionId $EditionId
        $lifecycle.Status | Should -Be $ExpectedStatus
        $lifecycle.Release | Should -Be $Release
    }

    It 'warns when support ends within 90 days' {
        $lifecycle = Get-TestLifecycleStatus -Build 22631 -EditionId 'Enterprise' -AsOf '2026-10-01'
        $lifecycle.Status | Should -Be 'EndingSoon'
        $lifecycle.DaysRemaining | Should -Be 40
    }

    It 'mentions ESU for Windows 10 22H2' {
        $lifecycle = Get-TestLifecycleStatus -Build 19045 -EditionId 'Core'
        $lifecycle.Message | Should -Match 'ESU'
    }

    It 'suggests a feature update for an unsupported Windows 11 release' {
        $lifecycle = Get-TestLifecycleStatus -Build 26100 -EditionId 'Core'
        $lifecycle.Message | Should -Match 'IncludeFeatureUpdates'
    }

    It 'distinguishes Windows Server 2025 from Windows 11 24H2 (same build 26100)' {
        $lifecycle = Get-TestLifecycleStatus -Build 26100 -EditionId 'ServerStandard' -InstallationType 'Server'
        $lifecycle.Status | Should -Be 'Supported'
        $lifecycle.EndOfUpdates | Should -Be '2034-11-14'
    }

    It 'reports Unknown for builds missing from the table (Insider Preview)' {
        $lifecycle = Get-TestLifecycleStatus -Build 27900 -EditionId 'Professional'
        $lifecycle.Status | Should -Be 'Unknown'
    }

    It 'reports EndOfSupport for old Windows 10 builds missing from the table' {
        $lifecycle = Get-TestLifecycleStatus -Build 18363 -EditionId 'Professional'
        $lifecycle.Status | Should -Be 'EndOfSupport'
    }
}

Describe 'Get-WinGetResult' {
    It 'treats exit code <ExitCode> as <ExpectedStatus>' -ForEach @(
        @{ ExitCode = 0; ExpectedStatus = 'Success'; Reboot = $false }
        @{ ExitCode = 3010; ExpectedStatus = 'Success'; Reboot = $true }        # reboot required
        @{ ExitCode = -1978335189; ExpectedStatus = 'Success'; Reboot = $false } # 0x8A15002B no applicable upgrade
        @{ ExitCode = -1978335212; ExpectedStatus = 'Success'; Reboot = $false } # 0x8A150014 no packages found
        @{ ExitCode = 1; ExpectedStatus = 'Warning'; Reboot = $false }
    ) {
        $result = Get-WinGetResult -ExitCode $ExitCode
        $result.Status | Should -Be $ExpectedStatus
        $result.RebootRequired | Should -Be $Reboot
    }

    It 'shows unknown exit codes in hexadecimal' {
        (Get-WinGetResult -ExitCode -1978334967).Message | Should -Match '0x8A150109'
    }
}

Describe 'Invoke-MaintenanceStep' {
    It 'returns the step result and records the duration' {
        $result = Invoke-MaintenanceStep -Action { New-StepResult -Status Warning -Message 'careful' }
        $result.Status | Should -Be 'Warning'
        $result.Message | Should -Be 'careful'
        $result.Duration | Should -BeOfType [timespan]
    }

    It 'turns an exception into a Failed result' {
        $result = Invoke-MaintenanceStep -Action { throw 'boom' }
        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Be 'boom'
    }

    It 'ignores stray pipeline output from a step' {
        $result = Invoke-MaintenanceStep -Action { 'noise'; 42; New-StepResult -Status Success -Message 'done' }
        $result.Message | Should -Be 'done'
    }
}

Describe 'Clear-StaleFile' {
    It 'deletes only files older than the cutoff' {
        $root = Join-Path -Path $TestDrive -ChildPath 'temp'
        $null = New-Item -Path (Join-Path $root 'sub') -ItemType Directory -Force
        $old = New-Item -Path (Join-Path $root 'sub\old.tmp') -ItemType File -Value ('x' * 1024)
        $new = New-Item -Path (Join-Path $root 'new.tmp') -ItemType File -Value 'keep'
        $old.LastWriteTime = (Get-Date).AddDays(-10)
        (Get-Item (Join-Path $root 'sub')).LastWriteTime = (Get-Date).AddDays(-10)

        $result = Clear-StaleFile -Path $root -OlderThan (Get-Date).AddDays(-2)

        $result.BytesFreed | Should -Be 1024
        Test-Path -LiteralPath $old.FullName | Should -BeFalse
        Test-Path -LiteralPath $new.FullName | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root 'sub') | Should -BeFalse
    }

    It 'handles a missing folder' {
        (Clear-StaleFile -Path (Join-Path $TestDrive 'missing') -OlderThan (Get-Date)).BytesFreed | Should -Be 0
    }

    It 'does not follow directory junctions (reparse points)' {
        $tempRoot = Join-Path -Path $TestDrive -ChildPath 'temp-junction-test'
        $externalDir = Join-Path -Path $TestDrive -ChildPath 'external-protected'
        $null = New-Item -Path $tempRoot -ItemType Directory -Force
        $null = New-Item -Path $externalDir -ItemType Directory -Force
        $externalFile = New-Item -Path (Join-Path $externalDir 'keep.txt') -ItemType File -Value 'important'
        $externalFile.LastWriteTime = (Get-Date).AddDays(-30)

        $junctionPath = Join-Path -Path $tempRoot -ChildPath 'link'
        $null = New-Item -ItemType Junction -Path $junctionPath -Target $externalDir

        try {
            $result = Clear-StaleFile -Path $tempRoot -OlderThan (Get-Date).AddDays(-2)
            $result.BytesFreed | Should -Be 0
            Test-Path -LiteralPath $externalFile.FullName | Should -BeTrue
        }
        finally {
            if (Test-Path -LiteralPath $junctionPath) {
                [System.IO.Directory]::Delete($junctionPath)
            }
        }
    }
}

Describe 'Invoke-CleanupStep' {
    It 'marks RebootRequired when DISM /StartComponentCleanup exits with 3010' {
        Mock Invoke-NativeCommand { return 3010 }
        Mock Get-TempFolderPath { return @() }
        Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'Delete-DeliveryOptimizationCache' }

        $result = Invoke-CleanupStep -TempFileAgeDays 2

        $result.Status | Should -Be 'Success'
        $result.RebootRequired | Should -BeTrue
    }
}

Describe 'Invoke-RepairStep' {
    It 'records RebootRequired for DISM 3010 and warns when SFC returns non-zero' {
        Mock Invoke-NativeCommand {
            if ($FilePath -like '*dism.exe') { return 3010 }
            return 1
        }

        $result = Invoke-RepairStep

        $result.Status | Should -Be 'Warning'
        $result.RebootRequired | Should -BeTrue
        $result.Message | Should -Match 'verification failed or unrepairable'
    }
}

Describe 'Invoke-UpgradeReadinessStep' {
    It 'falls back to Win32_ComputerSystem RAM on VMs and handles malformed TPM SpecVersion' {
        Mock Get-CimInstance {
            param($ClassName)
            switch ($ClassName) {
                'Win32_Tpm' { return [pscustomobject]@{ SpecVersion = 'invalid' } }
                'Win32_PhysicalMemory' { return @() }
                'Win32_ComputerSystem' { return [pscustomobject]@{ TotalPhysicalMemory = 8GB } }
                'Win32_Processor' { return [pscustomobject]@{ Name = $null; AddressWidth = 64; NumberOfCores = 4; MaxClockSpeed = 2400 } }
            }
        }
        Mock Get-ItemProperty { return [pscustomobject]@{ UEFISecureBootEnabled = 1 } }
        Mock Get-Partition { return $null }
        Mock Out-Host {}

        $result = Invoke-UpgradeReadinessStep

        $result.Status | Should -Be 'Warning'
        $result.Message | Should -Match '^Not ready for Windows 11: TPM 2\.0\.'
    }
}

Describe 'Step name lists (-Skip / -Only)' {
    BeforeAll {
        $parameters = (Get-Command -Name $mainScriptPath).Parameters

        function Test-StepParameterValue {
            param([string] $ParameterName, [string] $Value)
            $validator = $parameters[$ParameterName].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateScriptAttribute] }
            $null = $validator.ScriptBlock.InvokeWithContext($null, [psvariable]::new('_', $Value))
            $true
        }
    }

    It 'accepts the comma-separated form that powershell.exe -File passes for <ParameterName>' -ForEach @(
        @{ ParameterName = 'Skip' }
        @{ ParameterName = 'Only' }
    ) {
        Test-StepParameterValue -ParameterName $ParameterName -Value 'WinGet,WindowsUpdate' | Should -BeTrue
    }

    It 'rejects unknown step names for <ParameterName>' -ForEach @(
        @{ ParameterName = 'Skip' }
        @{ ParameterName = 'Only' }
    ) {
        { Test-StepParameterValue -ParameterName $ParameterName -Value 'WinGet,Bogus' } | Should -Throw '*Unknown step*Bogus*'
    }

    It 'flattens <Description>' -ForEach @(
        @{ Description = 'an array'; Value = @('Repair', 'Defender'); Expected = @('Repair', 'Defender') }
        @{ Description = 'a comma-separated string'; Value = @('Repair,Defender'); Expected = @('Repair', 'Defender') }
        @{ Description = 'mixed input with spaces, duplicates and empty items'; Value = @('Repair, defender', 'Repair,,'); Expected = @('Repair', 'Defender') }
    ) {
        $result = ConvertTo-StepNameList -Value $Value
        $result | Should -Be $Expected
    }

    It 'returns an empty array when nothing is given' {
        $result = ConvertTo-StepNameList -Value @()
        $result.Count | Should -Be 0
        , $result | Should -BeOfType [string[]]
    }
}

Describe 'Invoke-UpgradeReadinessStep TPM version parsing' {
    It 'reads a bare "2" SpecVersion as TPM 2.0' {
        Mock Get-CimInstance {
            param($ClassName)
            switch ($ClassName) {
                'Win32_Tpm' { return [pscustomobject]@{ SpecVersion = '2' } }
                'Win32_PhysicalMemory' { return [pscustomobject]@{ Capacity = 8GB } }
                'Win32_Processor' { return [pscustomobject]@{ Name = 'Test CPU'; AddressWidth = 64; NumberOfCores = 4; MaxClockSpeed = 2400 } }
            }
        }
        Mock Get-ItemProperty { return [pscustomobject]@{ UEFISecureBootEnabled = 1 } }
        Mock Get-Partition { return $null }
        Mock Out-Host {}

        (Invoke-UpgradeReadinessStep).Status | Should -Be 'Success'
    }
}

Describe 'Register-MaintenanceTask helpers' {
    It 'joins list values so -File keeps them in one token: <Value>' -ForEach @(
        @{ Value = '-Only WinGet, WindowsUpdate'; Expected = '-Only WinGet,WindowsUpdate' }
        @{ Value = '-Skip Repair ,Defender , Cleanup -AutoReboot'; Expected = '-Skip Repair,Defender,Cleanup -AutoReboot' }
        @{ Value = ''; Expected = '' }
    ) {
        Format-MaintenanceArgument -Arguments $Value | Should -Be $Expected
    }

    It 'accepts safe MaintenanceArguments: <Value>' -ForEach @(
        @{ Value = '' }
        @{ Value = '-Skip Repair, Defender' }
        @{ Value = "-Only WinGet, WindowsUpdate -LogDirectory 'C:\Logs'" }
    ) {
        Test-SafeMaintenanceArgument -Arguments $Value | Should -BeTrue
    }

    It 'rejects unsafe MaintenanceArguments: <Value>' -ForEach @(
        @{ Value = '-Skip Repair; calc.exe' }
        @{ Value = '$(whoami)' }
        @{ Value = '-Skip Repair | Out-Null' }
        @{ Value = '-Skip Repair & calc.exe' }
        @{ Value = '-LogDirectory "C:\Logs"' }
    ) {
        Test-SafeMaintenanceArgument -Arguments $Value | Should -BeFalse
    }

    It 'detects user-writable paths inside the user profile' {
        $userPath = Join-Path -Path $env:USERPROFILE -ChildPath 'Invoke-WindowsMaintenance.ps1'
        Test-IsPathUserWritable -Path $userPath | Should -BeTrue
    }

    It 'does not flag System32 binaries as user-writable' {
        $sysBinary = Join-Path -Path $env:SystemRoot -ChildPath 'System32\cmd.exe'
        Test-IsPathUserWritable -Path $sysBinary | Should -BeFalse
    }
}

Describe 'Get-ExceptionHResult' {
    It 'finds E_ACCESSDENIED behind the PowerShell and .NET wrappers' {
        # The real chain: MethodInvocationException -> UnauthorizedAccessException(0x80070005).
        $thrower = [pscustomobject]@{}
        $thrower | Add-Member -MemberType ScriptMethod -Name Fail -Value { [System.Runtime.InteropServices.Marshal]::ThrowExceptionForHR(-2147024891) }
        $caught = $null
        try { $thrower.Fail() } catch { $caught = $_ }

        $caught.Exception | Should -Not -BeOfType [System.Runtime.InteropServices.COMException]
        Get-ExceptionHResult -Exception $caught.Exception | Should -Be -2147024891
    }
}

Describe 'Windows Update reporting' {
    BeforeAll {
        # Test doubles for the Windows Update Agent COM API. Each fake update carries the
        # download and install results that the fake downloader and installer return.
        function Get-FakeUpdate {
            param(
                [string] $Title,
                [string] $Kb = '',
                [int] $ResultCode = 2,
                [int] $HResult = 0,
                [switch] $RebootRequired,
                [switch] $NotDownloaded,
                [int] $DownloadHResult = 0,
                [switch] $BrowseOnly,
                [switch] $FeatureUpdate,
                [switch] $NeedsUserInput
            )

            $categories = @()
            if ($FeatureUpdate) { $categories = @([pscustomobject]@{ CategoryID = '3689bdc8-b205-4af4-8d4b-a63924c5e9d5'; Name = 'Upgrades' }) }

            $update = [pscustomobject]@{
                Title                = $Title
                KBArticleIDs         = @($Kb | Where-Object { $_ })
                Identity             = [pscustomobject]@{ UpdateID = [guid]::NewGuid().Guid }
                BrowseOnly           = [bool]$BrowseOnly
                EulaAccepted         = $false
                IsDownloaded         = -not $NotDownloaded
                InstallationBehavior = [pscustomobject]@{ CanRequestUserInput = [bool]$NeedsUserInput }
                Categories           = $categories
                FakeDownload         = [pscustomobject]@{ ResultCode = $(if ($NotDownloaded) { 4 } else { 2 }); HResult = $DownloadHResult }
                FakeInstall          = [pscustomobject]@{ ResultCode = $ResultCode; HResult = $HResult; RebootRequired = [bool]$RebootRequired }
            }
            $update | Add-Member -MemberType ScriptMethod -Name AcceptEula -Value { $this.EulaAccepted = $true }
            $update
        }

        function Get-FakeUpdateSession {
            param(
                [object[]] $Updates = @(),
                [int] $DownloadThrows = 0,
                [int] $InstallThrows = 0
            )

            $session = [pscustomobject]@{
                ClientApplicationID = ''
                Found               = $Updates
                DownloadThrows      = $DownloadThrows
                InstallThrows       = $InstallThrows
            }
            $session | Add-Member -MemberType ScriptMethod -Name CreateUpdateSearcher -Value {
                $searcher = [pscustomobject]@{ Found = $this.Found }
                $searcher | Add-Member -MemberType ScriptMethod -Name Search -Value {
                    param($criteria)
                    $null = $criteria
                    [pscustomobject]@{ Updates = $this.Found }
                }
                $searcher
            }
            $session | Add-Member -MemberType ScriptMethod -Name CreateUpdateDownloader -Value {
                $downloader = [pscustomobject]@{ Updates = $null; Throws = $this.DownloadThrows }
                $downloader | Add-Member -MemberType ScriptMethod -Name Download -Value {
                    if ($this.Throws) { [System.Runtime.InteropServices.Marshal]::ThrowExceptionForHR($this.Throws) }
                    $result = [pscustomobject]@{ Updates = $this.Updates }
                    $result | Add-Member -MemberType ScriptMethod -Name GetUpdateResult -Value { param($index) $this.Updates.Item($index).FakeDownload }
                    $result
                }
                $downloader
            }
            $session | Add-Member -MemberType ScriptMethod -Name CreateUpdateInstaller -Value {
                $installer = [pscustomobject]@{ Updates = $null; Throws = $this.InstallThrows }
                $installer | Add-Member -MemberType ScriptMethod -Name Install -Value {
                    if ($this.Throws) { [System.Runtime.InteropServices.Marshal]::ThrowExceptionForHR($this.Throws) }
                    $needsRestart = @($this.Updates | Where-Object { $_.FakeInstall.RebootRequired }).Count -gt 0
                    $result = [pscustomobject]@{ Updates = $this.Updates; RebootRequired = $needsRestart }
                    $result | Add-Member -MemberType ScriptMethod -Name GetUpdateResult -Value { param($index) $this.Updates.Item($index).FakeInstall }
                    $result
                }
                $installer
            }
            $session
        }
    }

    BeforeEach {
        Mock Write-MaintenanceLog {}
        Mock New-Object -ParameterFilter { $ComObject -eq 'Microsoft.Update.UpdateColl' } -MockWith { , [System.Collections.ArrayList]::new() }
    }

    Context 'one update installs and needs a restart, another fails (scheduled overnight run)' {
        BeforeEach {
            $fakeSession = Get-FakeUpdateSession -Updates @(
                (Get-FakeUpdate -Title '2026-11 Cumulative Update' -Kb '5070001' -RebootRequired)
                (Get-FakeUpdate -Title 'Servicing Stack Update' -Kb '5070002' -ResultCode 4 -HResult -2145124318)
            )
            Mock New-Object -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' } -MockWith { $fakeSession }
        }

        It 'returns Warning, flags the restart and names the failed update in the message' {
            $result = Invoke-WindowsUpdateStep

            $result.Status | Should -Be 'Warning'
            $result.RebootRequired | Should -BeTrue
            $result.Message | Should -Be '1 installed, 1 failed (KB5070002). Restart required.'
        }

        It 'records each update with its result, HRESULT and restart need' {
            $details = (Invoke-WindowsUpdateStep).Details

            $details.Count | Should -Be 2
            $installed = $details | Where-Object { $_.KB -eq 'KB5070001' }
            $installed.Result | Should -Be 'Installed'
            $installed.RebootRequired | Should -BeTrue
            $installed.HResult | Should -BeNullOrEmpty

            $failed = $details | Where-Object { $_.KB -eq 'KB5070002' }
            $failed.Result | Should -Be 'Failed'
            $failed.HResult | Should -Be '0x80240022'
            $failed.Title | Should -Be 'Servicing Stack Update'
        }

        It 'keeps the details in the JSON report read the next morning' {
            $step = Invoke-MaintenanceStep -Action { Invoke-WindowsUpdateStep }
            $report = [ordered]@{
                steps           = @([pscustomobject]@{ Step = 'WindowsUpdate'; Status = $step.Status; Message = $step.Message; Details = $step.Details })
                rebootRequired  = $step.RebootRequired
                rebootScheduled = $false
            }

            $json = ConvertTo-MaintenanceReportJson -Report $report
            $json | Should -Not -Match 'System\.Management\.Automation'
            $parsed = $json | ConvertFrom-Json

            $parsed.rebootRequired | Should -BeTrue
            $parsed.rebootScheduled | Should -BeFalse
            $parsed.steps[0].Details[1].Result | Should -Be 'Failed'
            $parsed.steps[0].Details[1].HResult | Should -Be '0x80240022'
            $parsed.steps[0].Details[0].RebootRequired | Should -BeTrue
        }
    }

    It 'returns Failed when every attempted update fails' {
        $fakeSession = Get-FakeUpdateSession -Updates @(
            (Get-FakeUpdate -Title 'Update A' -Kb '1' -ResultCode 4 -HResult -2145124318)
            (Get-FakeUpdate -Title 'Update B' -Kb '2' -ResultCode 5)
        )
        Mock New-Object -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' } -MockWith { $fakeSession }

        $result = Invoke-WindowsUpdateStep

        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Be '0 installed, 2 failed (KB1, KB2).'
        ($result.Details | Where-Object { $_.KB -eq 'KB2' }).Result | Should -Be 'Aborted'
    }

    It 'reports download failures per update and installs the rest' {
        $fakeSession = Get-FakeUpdateSession -Updates @(
            (Get-FakeUpdate -Title 'Downloads fine' -Kb '10')
            (Get-FakeUpdate -Title 'Download breaks' -Kb '11' -NotDownloaded -DownloadHResult -2145107924)
        )
        Mock New-Object -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' } -MockWith { $fakeSession }

        $result = Invoke-WindowsUpdateStep

        $result.Status | Should -Be 'Warning'
        $result.Message | Should -Be '1 installed, 1 failed (KB11).'
        $broken = $result.Details | Where-Object { $_.KB -eq 'KB11' }
        $broken.Result | Should -Be 'DownloadFailed'
        $broken.HResult | Should -Be '0x8024402C'
    }

    It 'returns Failed with a network hint when nothing can be downloaded' {
        $fakeSession = Get-FakeUpdateSession -Updates @((Get-FakeUpdate -Title 'Offline' -Kb '20' -NotDownloaded))
        Mock New-Object -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' } -MockWith { $fakeSession }

        $result = Invoke-WindowsUpdateStep

        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Match 'check the network connection'
    }

    It 'explains E_ACCESSDENIED from a remote session instead of a generic error' {
        $fakeSession = Get-FakeUpdateSession -Updates @((Get-FakeUpdate -Title 'Remote' -Kb '30')) -DownloadThrows -2147024891
        Mock New-Object -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' } -MockWith { $fakeSession }

        $result = Invoke-WindowsUpdateStep

        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Match 'download denied \(0x80070005\).*remote sessions'
        $result.Details[0].Result | Should -Be 'DownloadFailed'
        $result.Details[0].HResult | Should -Be '0x80070005'
    }

    It 'reports the HRESULT when Install() fails for the whole batch' {
        $fakeSession = Get-FakeUpdateSession -Updates @((Get-FakeUpdate -Title 'Batch' -Kb '40')) -InstallThrows -2145124329
        Mock New-Object -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' } -MockWith { $fakeSession }

        $result = Invoke-WindowsUpdateStep

        $result.Status | Should -Be 'Failed'
        $result.Message | Should -Match '^Windows Update install failed \(0x80240017\)'
        $result.Details[0].Result | Should -Be 'Failed'
        $result.Details[0].HResult | Should -Be '0x80240017'
    }

    It 'lists updates left for later with the reason' {
        $fakeSession = Get-FakeUpdateSession -Updates @(
            (Get-FakeUpdate -Title 'Optional preview' -Kb '50' -BrowseOnly)
            (Get-FakeUpdate -Title 'Windows 11, version 26H2' -FeatureUpdate)
            (Get-FakeUpdate -Title 'Interactive' -Kb '52' -NeedsUserInput)
        )
        Mock New-Object -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' } -MockWith { $fakeSession }

        $result = Invoke-WindowsUpdateStep

        $result.Status | Should -Be 'Success'
        $result.Message | Should -Be '3 left for later (optional, feature or interactive).'
        @($result.Details.Reason) | Should -Be @('Optional', 'FeatureUpdate', 'NeedsUserInput')
        @($result.Details | Where-Object { $_.Result -ne 'NotInstalled' }).Count | Should -Be 0
    }

    It 'installs feature updates with -IncludeFeatureUpdates and accepts the EULA' {
        $feature = Get-FakeUpdate -Title 'Windows 11, version 26H2' -FeatureUpdate
        $fakeSession = Get-FakeUpdateSession -Updates @($feature)
        Mock New-Object -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' } -MockWith { $fakeSession }

        $result = Invoke-WindowsUpdateStep -IncludeFeatureUpdates

        $result.Details[0].Result | Should -Be 'Installed'
        $result.Details[0].KB | Should -BeNullOrEmpty
        $feature.EulaAccepted | Should -BeTrue
    }

    It 'says so when there is nothing to install' {
        $fakeSession = Get-FakeUpdateSession -Updates @()
        Mock New-Object -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' } -MockWith { $fakeSession }

        $result = Invoke-WindowsUpdateStep

        $result.Status | Should -Be 'Success'
        $result.Message | Should -Be 'No pending updates.'
    }
}

Describe 'Get-WindowsUpdateSummary' {
    It 'treats InstalledWithErrors as a warning' {
        $summary = Get-WindowsUpdateSummary -Record @([pscustomobject]@{ Result = 'InstalledWithErrors'; KB = 'KB1'; Title = 'A' })
        $summary.Status | Should -Be 'Warning'
        $summary.Message | Should -Be '0 installed, 1 installed with errors.'
    }

    It 'names updates without a KB by title' {
        $summary = Get-WindowsUpdateSummary -Record @(
            [pscustomobject]@{ Result = 'Installed'; KB = 'KB1'; Title = 'A' }
            [pscustomobject]@{ Result = 'Failed'; KB = $null; Title = 'Defender platform' }
        )
        $summary.Message | Should -Be '1 installed, 1 failed (Defender platform).'
    }
}

Describe 'Start-DelayedRestart' {
    It 'does not run shutdown.exe under -WhatIf' {
        # Points at a folder without shutdown.exe, so a regression fails the test instead of restarting the PC.
        Mock Get-NativeSystemPath { $TestDrive }
        Mock Write-MaintenanceLog {}

        Start-DelayedRestart -WhatIf | Should -BeFalse
    }

    Context 'output of the shutdown command' {
        BeforeAll {
            Mock Write-MaintenanceLog {}

            # Stand-ins for shutdown.exe that print text, like a localized error message.
            function Get-FakeShutdown {
                param([string] $Name, [int] $ExitCode)
                $path = Join-Path -Path $TestDrive -ChildPath "$Name.cmd"
                Set-Content -LiteralPath $path -Encoding Ascii -Value @(
                    '@echo off'
                    'echo A system shutdown has already been scheduled.(1190)'
                    "exit /b $ExitCode"
                )
                $path
            }
        }

        It 'returns exactly $false, not an array, when shutdown fails and prints text' {
            $result = Start-DelayedRestart -ShutdownPath (Get-FakeShutdown -Name 'busy' -ExitCode 1190) -Confirm:$false

            , $result | Should -BeOfType [bool]
            $result | Should -BeFalse
        }

        It 'returns exactly $true when shutdown succeeds and prints text' {
            $result = Start-DelayedRestart -ShutdownPath (Get-FakeShutdown -Name 'ok' -ExitCode 0) -Confirm:$false

            , $result | Should -BeOfType [bool]
            $result | Should -BeTrue
        }
    }
}

Describe 'Format-ErrorRecord' {
    It 'adds the HRESULT of a COM error wrapped by PowerShell' {
        $thrower = [pscustomobject]@{}
        # A COM error whose message does not already contain the code.
        $thrower | Add-Member -MemberType ScriptMethod -Name Search -Value { throw (New-Object -TypeName System.Runtime.InteropServices.COMException -ArgumentList 'Search failed', -2145124329) }
        $caught = $null
        try { $thrower.Search() } catch { $caught = $_ }

        $caught.Exception | Should -Not -BeOfType [System.Runtime.InteropServices.COMException]
        Format-ErrorRecord -ErrorRecord $caught | Should -Match 'Search failed.*\(0x80240017\)$'
    }

    It 'leaves plain script errors unchanged' {
        $caught = $null
        try { throw 'plain failure' } catch { $caught = $_ }

        Format-ErrorRecord -ErrorRecord $caught | Should -Be 'plain failure'
    }
}

Describe 'Single-instance lock' {
    BeforeAll {
        # A second PowerShell process holds the lock, like a scheduled run in progress.
        # Modes: Hold (Enter-MaintenanceLock and wait), Abandon (take it and exit without
        # releasing), Squat (a plain mutex created without this script, as another user would).
        $holderScript = Join-Path -Path $TestDrive -ChildPath 'Hold-Lock.ps1'
        Set-Content -LiteralPath $holderScript -Encoding Ascii -Value @'
param([string] $ScriptPath, [string] $Name, [string] $Mode, [string] $ReadyFile, [string] $ExitFile)
. $ScriptPath
switch ($Mode) {
    'Hold' { $lock = Enter-MaintenanceLock -Name $Name; $status = $lock.Status }
    'Abandon' { $lock = Enter-MaintenanceLock -Name $Name; $status = $lock.Status }
    'Squat' { $squat = [System.Threading.Mutex]::new($true, $Name); $status = 'Squatting' }
    'SquatHidden' {
        # Allows SYNCHRONIZE so the mutex can be opened, but nobody may read its owner:
        # the OWNER RIGHTS (S-1-3-4) entry removes the owner's implicit READ_CONTROL.
        if ($PSVersionTable.PSEdition -eq 'Core') { Add-Type -AssemblyName 'System.Threading.AccessControl' }
        $rights = [System.Security.AccessControl.MutexRights]'Synchronize, Modify'
        $security = New-Object -TypeName System.Security.AccessControl.MutexSecurity
        foreach ($sid in @([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-3-4', 'S-1-5-32-544')) {
            $identity = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList $sid
            $security.AddAccessRule((New-Object -TypeName System.Security.AccessControl.MutexAccessRule -ArgumentList $identity, $rights, 'Allow'))
        }
        $created = $false
        $mutexAcl = 'System.Threading.MutexAcl' -as [type]
        if ($mutexAcl) { $squat = $mutexAcl::Create($true, $Name, [ref]$created, $security) }
        else { $squat = [System.Threading.Mutex]::new($true, $Name, [ref]$created, $security) }
        $status = 'Squatting'
    }
}
Set-Content -LiteralPath $ReadyFile -Value $status
$deadline = (Get-Date).AddSeconds(60)
while (-not (Test-Path -LiteralPath $ExitFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
if ($Mode -eq 'Hold') { Exit-MaintenanceLock -Lock $lock }
# 'Abandon' and 'Squat' exit without releasing; Windows marks the mutex abandoned.
'@

        function Open-LockHolder {
            param([string] $Name, [string] $Mode)
            $id = [guid]::NewGuid().Guid
            $ready = Join-Path -Path $TestDrive -ChildPath "$id.ready"
            $exitFile = Join-Path -Path $TestDrive -ChildPath "$id.exit"
            $exe = (Get-Process -Id $PID).Path
            $process = Start-Process -FilePath $exe -PassThru -WindowStyle Hidden -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$holderScript`"",
                '-ScriptPath', "`"$mainScriptPath`"", '-Name', $Name, '-Mode', $Mode,
                '-ReadyFile', "`"$ready`"", '-ExitFile', "`"$exitFile`""
            )
            $deadline = (Get-Date).AddSeconds(30)
            while (-not (Test-Path -LiteralPath $ready) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
            [pscustomobject]@{
                Process  = $process
                Status   = $(if (Test-Path -LiteralPath $ready) { (Get-Content -LiteralPath $ready -Raw).Trim() } else { 'NotReady' })
                ExitFile = $exitFile
            }
        }

        function Close-LockHolder {
            param([object] $Holder)
            if (-not $Holder) { return }
            Set-Content -LiteralPath $Holder.ExitFile -Value 'exit'
            if (-not $Holder.Process.WaitForExit(15000)) { $Holder.Process.Kill() }
        }
    }

    BeforeEach {
        # A unique name per test, so tests never collide with a real run or each other.
        $lockName = 'Global\WindowsHealthAndUpdate-Test-' + [guid]::NewGuid().Guid
        $holder = $null
        $lock = $null
    }

    AfterEach {
        Exit-MaintenanceLock -Lock $lock
        Close-LockHolder -Holder $holder
    }

    It 'acquires a free lock and lets the next run take it after release' {
        $lock = Enter-MaintenanceLock -Name $lockName
        $lock.Status | Should -Be 'Acquired'
        $lock.Abandoned | Should -BeFalse
        Exit-MaintenanceLock -Lock $lock

        $lock = Enter-MaintenanceLock -Name $lockName
        $lock.Status | Should -Be 'Acquired'
    }

    It 'reports Busy while another process holds the lock' {
        $holder = Open-LockHolder -Name $lockName -Mode Hold
        $holder.Status | Should -Be 'Acquired'

        $lock = Enter-MaintenanceLock -Name $lockName

        $lock.Status | Should -Be 'Busy'
        $lock.Mutex | Should -BeNullOrEmpty
        $lock.Message | Should -Match 'already in progress'
    }

    It 'takes over and flags a run that ended without releasing the lock' {
        $holder = Open-LockHolder -Name $lockName -Mode Abandon
        $holder.Status | Should -Be 'Acquired'
        # Keep the mutex alive after the holder exits, as a second waiting run would.
        $keeper = [System.Threading.Mutex]::OpenExisting($lockName)
        try {
            Close-LockHolder -Holder $holder
            $holder = $null

            $lock = Enter-MaintenanceLock -Name $lockName

            $lock.Status | Should -Be 'Acquired'
            $lock.Abandoned | Should -BeTrue
            $lock.Message | Should -Match 'ended without finishing'
        }
        finally {
            $keeper.Dispose()
        }
    }

    It 'ignores a held lock created by an untrusted account instead of being blocked by it' {
        # Only SYSTEM is trusted here, so a mutex created and held by this test account
        # (owned by it, or by Administrators when elevated) plays the role of one created
        # by a standard user to block maintenance.
        $holder = Open-LockHolder -Name $lockName -Mode Squat
        $holder.Status | Should -Be 'Squatting'

        $lock = Enter-MaintenanceLock -Name $lockName -TrustedSid 'S-1-5-18'

        $lock.Status | Should -Be 'Untrusted'
        $lock.Owner | Should -Not -BeNullOrEmpty
        $lock.Message | Should -Match 'untrusted account'
    }

    It 'treats a held lock that hides its owner as untrusted' {
        $holder = Open-LockHolder -Name $lockName -Mode SquatHidden
        $holder.Status | Should -Be 'Squatting'

        $lock = Enter-MaintenanceLock -Name $lockName

        $lock.Status | Should -Be 'Untrusted'
        # Windows PowerShell 5.1 opens the mutex with reduced rights and fails to read the
        # owner; PowerShell 7 (MutexAcl) asks for full access and cannot open it at all.
        $lock.Message | Should -Match 'hides its owner|cannot open it'
    }

    It 'honours a held lock created by a trusted account' {
        $holder = Open-LockHolder -Name $lockName -Mode Squat
        $owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value

        # Same mutex as above, but its owner (this account, or Administrators when elevated) is trusted.
        $lock = Enter-MaintenanceLock -Name $lockName -TrustedSid 'S-1-5-32-544', $owner

        $lock.Status | Should -Be 'Busy'
    }
}
