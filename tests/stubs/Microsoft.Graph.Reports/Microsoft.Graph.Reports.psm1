# Test stub with fictitious data only. Never contains real tenant data.
function Get-MgReportAuthenticationMethodUserRegistrationDetail { param([switch]$All)
    @(
        [pscustomobject]@{ Id = 'u1'; UserPrincipalName = 'jan@fiktivni.example'; UserDisplayName = 'Jan Novák'; UserType = 'member'; IsAdmin = $true
            IsMfaRegistered = $false; IsMfaCapable = $false; MethodsRegistered = @('email'); SystemPreferredAuthenticationMethods = @() },
        [pscustomobject]@{ Id = 'u3'; UserPrincipalName = 'host_ext#EXT#@fiktivni.example'; UserDisplayName = 'Host'; UserType = 'guest'; IsAdmin = $false
            IsMfaRegistered = $true; IsMfaCapable = $true; MethodsRegistered = @('microsoftAuthenticatorPush') }
    )
}
