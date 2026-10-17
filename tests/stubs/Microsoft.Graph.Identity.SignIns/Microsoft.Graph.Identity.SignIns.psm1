# Test stub with fictitious data only. Never contains real tenant data.
function Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy { [pscustomobject]@{ DisplayName = 'Security Defaults'; IsEnabled = $false } }
function Get-MgIdentityConditionalAccessPolicy { param([switch]$All)
    @([pscustomobject]@{ DisplayName = 'Block legacy auth'; State = 'enabledForReportingButNotEnforced'
        Conditions = [pscustomobject]@{ Users = [pscustomobject]@{ IncludeUsers = @('All') }; ClientAppTypes = @('exchangeActiveSync', 'other') }
        GrantControls = [pscustomobject]@{ Operator = 'OR'; BuiltInControls = @('block') } })
}
