#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares variables from BeforeDiscovery/BeforeAll with It blocks.')]
param()

BeforeAll {
    $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Invoke-WindowsMaintenance.ps1'
    $schedulerPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Register-MaintenanceTask.ps1'
    # Dot-sourcing loads the functions only; the entry points return early.
    . $scriptPath
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

Describe 'Register-MaintenanceTask helpers' {
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
