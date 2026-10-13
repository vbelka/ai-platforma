<#
.SYNOPSIS
    WS0 audit: stav MFA – registrace metod, výchozí zabezpečení (security defaults), přehled podmíněného přístupu.

.DESCRIPTION
    REŽIM: POUZE ČTENÍ. Skript nic nemění v tenantu (používá jen Get-* cmdlety Microsoft Graph).
    Spouští výhradně administrátor (člověk).

    Dopad na tenant:
      - Žádná změna konfigurace ani uživatelů.
      - Možná výzva k souhlasu (consent) aplikace "Microsoft Graph Command Line Tools" – viz README, kap. Souhlas.

    Oprávnění Graph (delegovaná, jen čtení):
      - AuditLog.Read.All   (userRegistrationDetails – least privileged)
      - Policy.Read.All     (security defaults, conditional access policies)
      - User.Read.All       (doplnění stavu účtu – report nevrací zakázané uživatele)
    Role přihlášeného účtu (pro registrační report): Reports Reader, Security Reader,
    Security Administrator nebo Global Reader. Doporučeno: Global Reader.

    Důležité: registrační report ukazuje, kdo MÁ zaregistrovanou MFA metodu, ne zda je MFA VYNUCENO.
    Vynucení plyne z výchozího zabezpečení nebo podmíněného přístupu (oba exportuje tento skript)
    a z případného starého „per-user MFA“ (ručně v Entra admin center – viz checklist WS0).

    Výstupy:
      mfa-registration.csv        uživatel × registrované metody, isMfaRegistered/Capable, isAdmin
      mfa-admins-without-mfa.csv  správci bez schopnosti MFA (kritický nález)
      mfa-security-defaults.json  stav výchozího zabezpečení
      mfa-conditional-access.csv  zásady podmíněného přístupu (stav, vyžadované ovládací prvky)
      mfa-summary.json            souhrn

    Ověřeno (zdroj Microsoft Learn, 2026-10-13):
      https://learn.microsoft.com/graph/api/authenticationmethodsroot-list-userregistrationdetails
      https://learn.microsoft.com/graph/api/resources/userregistrationdetails
      https://learn.microsoft.com/graph/api/identitysecuritydefaultsenforcementpolicy-get
      https://learn.microsoft.com/graph/api/conditionalaccessroot-list-policies
      https://learn.microsoft.com/powershell/module/microsoft.graph.reports/get-mgreportauthenticationmethoduserregistrationdetail

.PARAMETER OutputPath
    Cílová složka. Výchozí <repo>/reports/<yyyy-MM-dd>_WS0 (mimo Git).

.PARAMETER TenantId
    Volitelné. Doména tenantu. Neukládat do repozitáře.

.EXAMPLE
    .\Get-WS0MfaReport.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$TenantId
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AuditCommon.psm1') -Force
Assert-AuditModule -Name 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Users', 'Microsoft.Graph.Reports', 'Microsoft.Graph.Identity.SignIns'

$connectParams = @{ Scopes = @('AuditLog.Read.All', 'Policy.Read.All', 'User.Read.All'); ContextScope = 'Process'; NoWelcome = $true }
if ($TenantId) { $connectParams.TenantId = $TenantId }
Connect-MgGraph @connectParams

$folder = Get-AuditOutputFolder -OutputPath $OutputPath
Write-Host "WS0 MFA – výstupy: $folder"

# --- 1) Registration details ------------------------------------------------------------
$registrations = @(Get-MgReportAuthenticationMethodUserRegistrationDetail -All)

# The report does not return disabled users – add account state from the directory.
$users = @(Get-MgUser -All -Property 'id', 'userPrincipalName', 'accountEnabled' -PageSize 999)
$enabledById = @{}
foreach ($u in $users) { $enabledById[$u.Id] = $u.AccountEnabled }

$regRows = foreach ($r in $registrations) {
    [pscustomobject]@{
        UserPrincipalName       = $r.UserPrincipalName
        DisplayName             = $r.UserDisplayName
        UserType                = $r.UserType
        AccountEnabled          = $enabledById[$r.Id]
        IsAdmin                 = $r.IsAdmin
        IsMfaRegistered         = $r.IsMfaRegistered
        IsMfaCapable            = $r.IsMfaCapable
        IsPasswordlessCapable   = $r.IsPasswordlessCapable
        IsSsprCapable           = $r.IsSsprCapable
        MethodsRegistered       = Join-AuditValue $r.MethodsRegistered
        UserPreferredMethod     = $r.UserPreferredMethodForSecondaryAuthentication
        SystemPreferredMethods  = Join-AuditValue $r.SystemPreferredAuthenticationMethods
        LastUpdatedDateTime     = $r.LastUpdatedDateTime
    }
}
Export-AuditCsv -InputObject @($regRows) -Folder $folder -FileName 'mfa-registration.csv'

$adminsWithoutMfa = @($regRows | Where-Object { $_.IsAdmin -and -not $_.IsMfaCapable })
Export-AuditCsv -InputObject $adminsWithoutMfa -Folder $folder -FileName 'mfa-admins-without-mfa.csv'

# --- 2) Security defaults ---------------------------------------------------------------
$securityDefaults = Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy
Export-AuditJson -InputObject ([ordered]@{
        DisplayName = $securityDefaults.DisplayName
        IsEnabled   = $securityDefaults.IsEnabled
    }) -Folder $folder -FileName 'mfa-security-defaults.json'

# --- 3) Conditional Access (may be unavailable without Entra ID P1) ----------------------
$caRows = @()
$caError = $null
try {
    $policies = @(Get-MgIdentityConditionalAccessPolicy -All)
    $caRows = foreach ($p in $policies) {
        [pscustomobject]@{
            DisplayName          = $p.DisplayName
            State                = $p.State
            IncludeUsers         = Join-AuditValue $p.Conditions.Users.IncludeUsers
            ExcludeUsers         = Join-AuditValue $p.Conditions.Users.ExcludeUsers
            IncludeGroups        = Join-AuditValue $p.Conditions.Users.IncludeGroups
            ExcludeGroups        = Join-AuditValue $p.Conditions.Users.ExcludeGroups
            IncludeRoles         = Join-AuditValue $p.Conditions.Users.IncludeRoles
            IncludeApplications  = Join-AuditValue $p.Conditions.Applications.IncludeApplications
            ClientAppTypes       = Join-AuditValue $p.Conditions.ClientAppTypes
            GrantOperator        = $p.GrantControls.Operator
            BuiltInControls      = Join-AuditValue $p.GrantControls.BuiltInControls
            AuthenticationStrength = $p.GrantControls.AuthenticationStrength.DisplayName
            RequiresMfa          = (@($p.GrantControls.BuiltInControls) -contains 'mfa') -or [bool]$p.GrantControls.AuthenticationStrength
            ModifiedDateTime     = $p.ModifiedDateTime
        }
    }
}
catch {
    $caError = $_.Exception.Message
    Write-Warning "Zásady podmíněného přístupu nelze načíst: $caError"
}
Export-AuditCsv -InputObject @($caRows) -Folder $folder -FileName 'mfa-conditional-access.csv'

# --- 4) Summary ---------------------------------------------------------------------------
$members = @($regRows | Where-Object { $_.UserType -eq 'member' })
$summary = [ordered]@{
    GeneratedAt                  = (Get-Date).ToString('s')
    RegistrationRecords          = $regRows.Count
    MembersTotal                 = $members.Count
    MembersMfaCapable            = @($members | Where-Object IsMfaCapable).Count
    MembersNotMfaCapable         = @($members | Where-Object { -not $_.IsMfaCapable }).Count
    AdminsTotal                  = @($regRows | Where-Object IsAdmin).Count
    AdminsWithoutMfa             = $adminsWithoutMfa.Count
    SecurityDefaultsEnabled      = $securityDefaults.IsEnabled
    ConditionalAccessPolicies    = @($caRows).Count
    ConditionalAccessEnabledMfa  = @($caRows | Where-Object { $_.State -eq 'enabled' -and $_.RequiresMfa }).Count
    ConditionalAccessReadError   = $caError
    Note                         = 'Registrace MFA != vynucení MFA. Per-user MFA ověřit ručně (checklist WS0).'
}
Export-AuditJson -InputObject $summary -Folder $folder -FileName 'mfa-summary.json'

Disconnect-MgGraph | Out-Null
Write-Host 'Hotovo. Nic nebylo změněno.'
