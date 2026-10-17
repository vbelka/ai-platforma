<#
.SYNOPSIS
    WS0 audit: přehled licencí (SKU), servisních plánů a licencí/plánů jednotlivých uživatelů.

.DESCRIPTION
    REŽIM: POUZE ČTENÍ. Skript nic nemění v tenantu (používá jen Get-* cmdlety Microsoft Graph).
    Spouští výhradně administrátor (člověk).

    Dopad na tenant:
      - Žádná změna konfigurace, uživatelů ani licencí.
      - Při prvním přihlášení k aplikaci "Microsoft Graph Command Line Tools" může Entra ID vyžádat
        souhlas (consent) s oprávněními níže. Udělení souhlasu správcem za organizaci JE změna tenantu
        (vznikne/rozšíří se enterprise aplikace). Viz scripts/audit/README.md, kap. Souhlas.

    Oprávnění Graph (delegovaná, jen čtení):
      - LicenseAssignment.Read.All  (List subscribedSkus – least privileged)
      - User.Read.All               (seznam uživatelů, assignedLicenses, licenseAssignmentStates)
      - AuditLog.Read.All           (jen s -IncludeSignInActivity; signInActivity vyžaduje Entra ID P1/P2)
    Doporučená role přihlášeného účtu: Global Reader (Globální čtenář).

    Výstupy (do -OutputPath, výchozí <repo>/reports/<datum>_WS0):
      licenses-skus.csv            předplacené SKU, počty zakoupených/přiřazených/volných licencí
      licenses-sku-plans.csv       servisní plány obsažené v jednotlivých SKU
      users-licenses.csv           uživatel × přiřazené SKU (přímo/skupinou, chyby přiřazení, vypnuté plány)
      users-service-plans.csv      uživatel × servisní plán (zapnutý/vypnutý) – pro posouzení Copilot/Teams/SPO
      licenses-summary.json        souhrn

    Ověřeno (zdroj Microsoft Learn, 2026-10-13):
      https://learn.microsoft.com/graph/api/subscribedsku-list
      https://learn.microsoft.com/graph/api/user-list
      https://learn.microsoft.com/graph/api/resources/licenseassignmentstate
      https://learn.microsoft.com/powershell/module/microsoft.graph.identity.directorymanagement/get-mgsubscribedsku
      https://learn.microsoft.com/powershell/module/microsoft.graph.users/get-mguser

.PARAMETER OutputPath
    Cílová složka. Výchozí <repo>/reports/<yyyy-MM-dd>_WS0 (mimo Git).

.PARAMETER ClientId
    Volitelné. AppId vlastní auditní aplikace (scripts/identity/New-WS0AuditApp.ps1). Bez něj se použije
    Microsoft Graph Command Line Tools. Neukládat do repozitáře.

.PARAMETER TenantId
    Volitelné. Doména tenantu (např. contoso.onmicrosoft.com). Neukládat do repozitáře.

.PARAMETER IncludeSignInActivity
    Přidá datum posledního úspěšného přihlášení (nevyužité licence). Vyžaduje Entra ID P1/P2 a AuditLog.Read.All.

.EXAMPLE
    .\Get-WS0LicenseReport.ps1 -IncludeSignInActivity
#>
[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$TenantId,
    [string]$ClientId,
    [switch]$IncludeSignInActivity
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AuditCommon.psm1') -Force
Assert-AuditModule -Name 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Users', 'Microsoft.Graph.Identity.DirectoryManagement'

$scopes = @('LicenseAssignment.Read.All', 'User.Read.All')
if ($IncludeSignInActivity) { $scopes += 'AuditLog.Read.All' }

$ownsConnection = Connect-AuditGraph -Scopes $scopes -TenantId $TenantId -ClientId $ClientId

$folder = Get-AuditOutputFolder -OutputPath $OutputPath
Write-Host "WS0 licence – výstupy: $folder"

# --- 1) Subscribed SKUs ---------------------------------------------------------------
$skus = @(Get-MgSubscribedSku -All)
$skuById = @{}
$planNameById = @{}
foreach ($sku in $skus) {
    $skuById[[string]$sku.SkuId] = $sku
    foreach ($plan in $sku.ServicePlans) { $planNameById[[string]$plan.ServicePlanId] = $plan.ServicePlanName }
}

$skuRows = foreach ($sku in $skus) {
    [pscustomobject]@{
        SkuPartNumber    = $sku.SkuPartNumber
        SkuId            = $sku.SkuId
        AppliesTo        = $sku.AppliesTo
        CapabilityStatus = $sku.CapabilityStatus
        PrepaidEnabled   = $sku.PrepaidUnits.Enabled
        PrepaidWarning   = $sku.PrepaidUnits.Warning
        PrepaidSuspended = $sku.PrepaidUnits.Suspended
        ConsumedUnits    = $sku.ConsumedUnits
        AvailableUnits   = [int]$sku.PrepaidUnits.Enabled - [int]$sku.ConsumedUnits
        ServicePlanCount = @($sku.ServicePlans).Count
    }
}
Export-AuditCsv -InputObject @($skuRows) -Folder $folder -FileName 'licenses-skus.csv'

$skuPlanRows = foreach ($sku in $skus) {
    foreach ($plan in $sku.ServicePlans) {
        [pscustomobject]@{
            SkuPartNumber      = $sku.SkuPartNumber
            ServicePlanName    = $plan.ServicePlanName
            ServicePlanId      = $plan.ServicePlanId
            ProvisioningStatus = $plan.ProvisioningStatus
            AppliesTo          = $plan.AppliesTo
        }
    }
}
Export-AuditCsv -InputObject @($skuPlanRows) -Folder $folder -FileName 'licenses-sku-plans.csv'

# --- 2) Users and their licenses ---------------------------------------------------------
$userProps = @('id', 'displayName', 'userPrincipalName', 'accountEnabled', 'userType', 'createdDateTime',
    'usageLocation', 'assignedLicenses', 'licenseAssignmentStates')
if ($IncludeSignInActivity) { $userProps += 'signInActivity' }

$users = @(Get-MgUser -All -Property $userProps -PageSize 500)

$userLicenseRows = New-Object System.Collections.Generic.List[object]
$userPlanRows = New-Object System.Collections.Generic.List[object]

foreach ($user in $users) {
    $lastSignIn = $null
    if ($IncludeSignInActivity -and $user.SignInActivity) { $lastSignIn = $user.SignInActivity.LastSuccessfulSignInDateTime }

    $states = @($user.LicenseAssignmentStates)
    if ($states.Count -eq 0) {
        $userLicenseRows.Add([pscustomobject]@{
                UserPrincipalName     = $user.UserPrincipalName
                DisplayName           = $user.DisplayName
                AccountEnabled        = $user.AccountEnabled
                UserType              = $user.UserType
                UsageLocation         = $user.UsageLocation
                SkuPartNumber         = ''
                AssignedVia           = ''
                AssignmentState       = ''
                AssignmentError       = ''
                DisabledPlans         = ''
                LastSuccessfulSignIn  = $lastSignIn
                FlagDisabledButLicensed = $false
            })
        continue
    }

    foreach ($state in $states) {
        $sku = $skuById[[string]$state.SkuId]
        $skuName = if ($sku) { $sku.SkuPartNumber } else { [string]$state.SkuId }
        $disabled = @($state.DisabledPlans | ForEach-Object { if ($planNameById[[string]$_]) { $planNameById[[string]$_] } else { $_ } })

        $userLicenseRows.Add([pscustomobject]@{
                UserPrincipalName       = $user.UserPrincipalName
                DisplayName             = $user.DisplayName
                AccountEnabled          = $user.AccountEnabled
                UserType                = $user.UserType
                UsageLocation           = $user.UsageLocation
                SkuPartNumber           = $skuName
                AssignedVia             = if ($state.AssignedByGroup) { "Group:$($state.AssignedByGroup)" } else { 'Direct' }
                AssignmentState         = $state.State
                AssignmentError         = $state.Error
                DisabledPlans           = Join-AuditValue $disabled
                LastSuccessfulSignIn    = $lastSignIn
                FlagDisabledButLicensed = (-not $user.AccountEnabled)
            })

        if ($sku) {
            foreach ($plan in $sku.ServicePlans) {
                $userPlanRows.Add([pscustomobject]@{
                        UserPrincipalName = $user.UserPrincipalName
                        SkuPartNumber     = $sku.SkuPartNumber
                        ServicePlanName   = $plan.ServicePlanName
                        PlanEnabled       = -not (@($state.DisabledPlans) -contains [string]$plan.ServicePlanId)
                        AssignedVia       = if ($state.AssignedByGroup) { 'Group' } else { 'Direct' }
                    })
            }
        }
    }
}

Export-AuditCsv -InputObject $userLicenseRows.ToArray() -Folder $folder -FileName 'users-licenses.csv'
Export-AuditCsv -InputObject $userPlanRows.ToArray() -Folder $folder -FileName 'users-service-plans.csv'

# --- 3) Summary ---------------------------------------------------------------------------
$licensedUsers = @($users | Where-Object { @($_.AssignedLicenses).Count -gt 0 })
$summary = [ordered]@{
    GeneratedAt              = (Get-Date).ToString('s')
    SkuCount                 = $skus.Count
    UserCount                = $users.Count
    LicensedUserCount        = $licensedUsers.Count
    DisabledButLicensedCount = @($licensedUsers | Where-Object { -not $_.AccountEnabled }).Count
    GuestCount               = @($users | Where-Object { $_.UserType -eq 'Guest' }).Count
    AssignmentErrorCount     = @($userLicenseRows | Where-Object { $_.AssignmentError }).Count
    # Heuristic only: plan names containing "COPILOT". Exact SKU/plan names must be verified on Microsoft Learn.
    SkusWithCopilotPlan      = @($skus | Where-Object { $_.ServicePlans.ServicePlanName -match 'COPILOT' } | ForEach-Object SkuPartNumber)
    SignInActivityIncluded   = [bool]$IncludeSignInActivity
}
Export-AuditJson -InputObject $summary -Folder $folder -FileName 'licenses-summary.json'

if ($ownsConnection) { Disconnect-MgGraph | Out-Null }
Write-Host 'Hotovo. Nic nebylo změněno.'
