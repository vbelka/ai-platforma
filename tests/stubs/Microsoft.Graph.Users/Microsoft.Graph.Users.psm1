# Test stub with fictitious data only. Never contains real tenant data.
function Get-MgUser { param([switch]$All, $Property, $PageSize)
    @(
        [pscustomobject]@{ Id = 'u1'; DisplayName = 'Jan Novák'; UserPrincipalName = 'jan@fiktivni.example'; AccountEnabled = $true; UserType = 'Member'; UsageLocation = 'CZ'
            AssignedLicenses = @('x'); SignInActivity = [pscustomobject]@{ LastSuccessfulSignInDateTime = '2026-10-01' }
            LicenseAssignmentStates = @(
                [pscustomobject]@{ SkuId = 'sku-1'; AssignedByGroup = $null; DisabledPlans = @('p1'); State = 'Active'; Error = $null },
                [pscustomobject]@{ SkuId = 'sku-2'; AssignedByGroup = 'g1'; DisabledPlans = @(); State = 'Active'; Error = $null }) },
        [pscustomobject]@{ Id = 'u2'; DisplayName = 'Eva Svobodová'; UserPrincipalName = 'eva@fiktivni.example'; AccountEnabled = $false; UserType = 'Member'; UsageLocation = 'CZ'
            AssignedLicenses = @('x')
            LicenseAssignmentStates = @([pscustomobject]@{ SkuId = 'sku-1'; AssignedByGroup = $null; DisabledPlans = @(); State = 'Error'; Error = 'CountViolation' }) },
        [pscustomobject]@{ Id = 'u3'; DisplayName = 'Host'; UserPrincipalName = 'host_ext#EXT#@fiktivni.example'; AccountEnabled = $true; UserType = 'Guest'
            AssignedLicenses = @(); LicenseAssignmentStates = @() }
    )
}
