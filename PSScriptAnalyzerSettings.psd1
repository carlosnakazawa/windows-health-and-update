@{
    Severity = @('Error', 'Warning')

    Rules    = @{
        # The scripts must keep working on the Windows PowerShell 5.1 that ships with Windows.
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.4')
        }
    }
}
