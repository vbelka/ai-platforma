# Test stub with fictitious data only. Never contains real tenant data.
function Connect-SPOService { param($Url) }
function Disconnect-SPOService { }
function Get-SPOTenant {
    [pscustomobject]@{ SharingCapability = 'ExternalUserAndGuestSharing'; OneDriveSharingCapability = 'ExternalUserSharingOnly'
        DefaultSharingLinkType = 'None'; CoreDefaultShareLinkScope = 'Organization'; RequireAnonymousLinksExpireInDays = -1
        ShowEveryoneExceptExternalUsersClaim = $true }
}
function Get-SPOSite { param($Identity, $Limit, $IncludePersonalSite)
    $sites = @(
        [pscustomobject]@{ Url = 'https://fiktivni.sharepoint.com/sites/obchod'; Title = 'Obchod'; Template = 'GROUP#0' },
        [pscustomobject]@{ Url = 'https://fiktivni-my.sharepoint.com/personal/jan'; Title = 'Jan'; Template = 'SPSPERS#10' })
    if ($Identity) {
        [pscustomobject]@{ Url = $Identity; SharingCapability = $(if ($Identity -match 'obchod') { 'ExternalUserAndGuestSharing' } else { 'Disabled' })
            DefaultSharingLinkType = 'None'; SensitivityLabel = $null }
    }
    elseif ($IncludePersonalSite) { $sites } else { $sites[0] }
}
