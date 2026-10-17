# Test stub with fictitious data only. Never contains real tenant data.
$script:Created = New-Object System.Collections.Generic.List[string]
$script:ExistingNames = @()
function Set-StubExistingApplication([string[]]$Names) { $script:ExistingNames = $Names }
function Get-StubCreated { $script:Created.ToArray() }
function Reset-StubCreated { $script:Created.Clear() }
function Get-MgServicePrincipal { param($Filter, $Property)
    [pscustomobject]@{ Id = 'sp-graph'; AppId = '00000003-0000-0000-c000-000000000000'
        Oauth2PermissionScopes = @('LicenseAssignment.Read.All', 'User.Read.All', 'AuditLog.Read.All', 'Policy.Read.All', 'Group.Read.All', 'Directory.ReadWrite.All') |
            ForEach-Object { [pscustomobject]@{ Value = $_; Id = "scope-$_" } } }
}
function Get-MgApplication { param($Filter, $Property)
    foreach ($name in $script:ExistingNames) {
        if ($Filter -eq "displayName eq '$name'") { [pscustomobject]@{ Id = 'obj-1'; AppId = 'app-existing'; DisplayName = $name; RequiredResourceAccess = @() } }
    }
}
function New-MgApplication { param($DisplayName, $SignInAudience, $IsFallbackPublicClient, $PublicClient, $RequiredResourceAccess, $Notes)
    if ($SignInAudience -ne 'AzureADMyOrg' -or -not $IsFallbackPublicClient) { throw 'unexpected app settings' }
    if (@($RequiredResourceAccess[0].ResourceAccess | Where-Object { $_.Type -ne 'Scope' }).Count -gt 0) { throw 'only delegated scopes allowed' }
    $script:Created.Add("app:${DisplayName}:$(@($RequiredResourceAccess[0].ResourceAccess).Count)")
    [pscustomobject]@{ Id = 'obj-new'; AppId = 'app-new'; DisplayName = $DisplayName }
}
function New-MgServicePrincipal { param($AppId) $script:Created.Add("sp:$AppId"); [pscustomobject]@{ Id = 'sp-new'; AppId = $AppId } }
