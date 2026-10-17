@{
    # Shared lint settings for all PowerShell in this repository (used locally and in CI).
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Audit scripts are interactive tools run by an administrator; console output is intentional.
        'PSAvoidUsingWriteHost'
    )
}
