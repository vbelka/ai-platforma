<#
.SYNOPSIS
    WS1: registrace vlastní aplikace Entra ID pro opakované audity WS0 (jen delegovaná čtecí oprávnění).

.DESCRIPTION
    !!! SKRIPT MĚNÍ TENANT – ale jen s přepínačem -Apply. !!!
    Spouští výhradně administrátor (člověk), nikdy ne Claude.

    VÝCHOZÍ REŽIM: POUZE ČTENÍ (plán). Bez -Apply skript jen zjistí, zda aplikace existuje,
    přeloží názvy oprávnění na ID a vypíše, co by vytvořil. Nic nemění.
    -WhatIf: s -Apply ukáže jednotlivé změny a neprovede je.
    -Confirm: před každou změnou se zeptá (výchozí chování pro -Apply je dotaz jednou za změnu).

    Dopad na tenant s -Apply:
      1. Vznikne registrace aplikace (application) „<DisplayName>“:
         - jen pro tuto organizaci (SignInAudience = AzureADMyOrg),
         - veřejný klient (IsFallbackPublicClient = true, redirect URI http://localhost) – BEZ tajemství
           a certifikátu, přihlašuje se vždy konkrétní správce,
         - požadovaná delegovaná oprávnění Microsoft Graph (jen čtení):
           LicenseAssignment.Read.All, User.Read.All, AuditLog.Read.All, Policy.Read.All, Group.Read.All.
      2. Vznikne k ní service principal (enterprise aplikace) v tenantu.
      3. Souhlas správce (admin consent) skript NEUDĚLUJE. Udělí ho Global Administrator / Privileged
         Role Administrator ručně v Entra admin center (postup vypíše skript) – je to samostatná změna.
    Návrat zpět: Entra admin center → Registrace aplikací → aplikace → Odstranit
    (nebo Remove-MgApplication -ApplicationId <ObjectId>). Odstraněná aplikace je 30 dní v koši.

    Proč: audit pak nepotřebuje souhlas pro sdílenou aplikaci Microsoft Graph Command Line Tools
    a oprávnění auditu jsou v tenantu vidět pod jedním srozumitelným názvem.

    Oprávnění pro běh skriptu:
      plán:   Application.Read.All (Graph), role např. Global Reader
      -Apply: Application.ReadWrite.All (Graph; least privileged pro založení service principalu),
              role Application Administrator nebo Cloud Application Administrator.

    Ověřeno (zdroj Microsoft Learn, 2026-10-17):
      https://learn.microsoft.com/graph/api/application-post-applications
      https://learn.microsoft.com/graph/api/serviceprincipal-post-serviceprincipals
      https://learn.microsoft.com/graph/api/resources/application  (signInAudience, isFallbackPublicClient)
      https://learn.microsoft.com/graph/api/resources/requiredresourceaccess
      https://learn.microsoft.com/graph/api/resources/resourceaccess  (type Scope = delegované)
      https://learn.microsoft.com/powershell/module/microsoft.graph.applications/new-mgapplication
      https://learn.microsoft.com/powershell/module/microsoft.graph.applications/new-mgserviceprincipal

    Výstup: jen konzole. ID aplikace a tenantu se NEUKLÁDAJÍ do souborů – nezapisujte je do repozitáře.

.PARAMETER DisplayName
    Název aplikace. Výchozí „Cleversystems WS0 Audit (read-only)“.

.PARAMETER TenantId
    Volitelné. Doména tenantu. Neukládat do repozitáře.

.PARAMETER Apply
    Skutečně vytvoří aplikaci a service principal. Bez něj jen plán.

.EXAMPLE
    .\New-WS0AuditApp.ps1                 # plán, nic nemění
.EXAMPLE
    .\New-WS0AuditApp.ps1 -Apply -WhatIf  # ukáže změny, neprovede
.EXAMPLE
    .\New-WS0AuditApp.ps1 -Apply          # vytvoří aplikaci (s potvrzením)
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName = 'Cleversystems WS0 Audit (read-only)',
    [string]$TenantId,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'audit') 'AuditCommon.psm1') -Force
Assert-AuditModule -Name 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Applications'

# Well-known, public appId of the Microsoft Graph resource application (same in every tenant).
$graphAppId = '00000003-0000-0000-c000-000000000000'
$auditScopes = @('LicenseAssignment.Read.All', 'User.Read.All', 'AuditLog.Read.All', 'Policy.Read.All', 'Group.Read.All')

$runScopes = if ($Apply) { @('Application.ReadWrite.All') } else { @('Application.Read.All') }
$ownsConnection = Connect-AuditGraph -Scopes $runScopes -TenantId $TenantId

try {
    Write-Host ("Režim: {0}" -f $(if ($Apply) { 'ZMĚNA (-Apply)' } else { 'PLÁN – jen čtení, nic se nemění' })) -ForegroundColor Cyan

    # --- 1) Resolve delegated permission IDs from the Graph service principal in this tenant ---------
    $graphSp = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'" -Property 'id', 'appId', 'oauth2PermissionScopes'
    if (-not $graphSp) { throw 'Service principal Microsoft Graph nebyl v tenantu nalezen.' }

    $resourceAccess = foreach ($scope in $auditScopes) {
        $match = @($graphSp.Oauth2PermissionScopes | Where-Object { $_.Value -eq $scope })
        if ($match.Count -ne 1) { throw "Oprávnění '$scope' nebylo v Microsoft Graph nalezeno." }
        @{ Id = $match[0].Id; Type = 'Scope' }
    }
    Write-Host '  Delegovaná oprávnění Microsoft Graph (jen čtení):'
    $auditScopes | ForEach-Object { Write-Host "    - $_" }

    # --- 2) Existing app? ---------------------------------------------------------------------------
    $escapedName = $DisplayName.Replace("'", "''")
    $existing = @(Get-MgApplication -Filter "displayName eq '$escapedName'" -Property 'id', 'appId', 'displayName', 'requiredResourceAccess')
    if ($existing.Count -gt 0) {
        Write-Warning ("Aplikace '{0}' už existuje ({1}×). Skript nic nevytvoří." -f $DisplayName, $existing.Count)
        foreach ($app in $existing) {
            $graphAccess = @($app.RequiredResourceAccess | Where-Object { $_.ResourceAppId -eq $graphAppId }).ResourceAccess
            $missing = @($resourceAccess | Where-Object { @($graphAccess.Id) -notcontains $_.Id })
            Write-Host ("  AppId {0}: chybějících oprávnění {1}" -f $app.AppId, $missing.Count)
        }
        return
    }

    $appParams = @{
        DisplayName            = $DisplayName
        SignInAudience         = 'AzureADMyOrg'
        IsFallbackPublicClient = $true
        PublicClient           = @{ RedirectUris = @('http://localhost') }
        RequiredResourceAccess = @(@{ ResourceAppId = $graphAppId; ResourceAccess = @($resourceAccess) })
        Notes                  = 'WS0 audit, delegated read-only permissions. Created by scripts/identity/New-WS0AuditApp.ps1.'
    }

    Write-Host ''
    Write-Host 'Plánované změny:' -ForegroundColor Yellow
    Write-Host "  1. Registrace aplikace '$DisplayName' (jen tato organizace, veřejný klient, bez tajemství)"
    Write-Host '  2. Service principal (enterprise aplikace) k této registraci'
    Write-Host '  Souhlas správce: NEUDĚLUJE se – ručně, viz níže.'

    if (-not $Apply) {
        Write-Host ''
        Write-Host 'PLÁN dokončen. Nic nebylo změněno. Pro provedení spusťte s -Apply (případně nejdřív -Apply -WhatIf).' -ForegroundColor Green
        return
    }

    # --- 3) Apply ------------------------------------------------------------------------------------
    if (-not $PSCmdlet.ShouldProcess($DisplayName, 'Vytvořit registraci aplikace')) { return }
    $app = New-MgApplication @appParams
    Write-Host "  Vytvořena registrace aplikace. AppId: $($app.AppId)" -ForegroundColor Green

    if ($PSCmdlet.ShouldProcess($DisplayName, 'Vytvořit service principal')) {
        New-MgServicePrincipal -AppId $app.AppId | Out-Null
        Write-Host '  Vytvořen service principal.' -ForegroundColor Green
    }

    $tenant = (Get-MgContext).TenantId
    Write-Host ''
    Write-Host 'Další kroky (ručně, zapsat do protokolu změn WS1):' -ForegroundColor Yellow
    Write-Host '  1. Entra admin center → Identita → Aplikace → Registrace aplikací → Všechny aplikace'
    Write-Host "     → '$DisplayName' → Oprávnění rozhraní API → Udělit souhlas správce pro organizaci."
    Write-Host '  2. Audit pak spouštějte s vlastní aplikací:'
    Write-Host "     .\scripts\audit\Invoke-WS0Audit.ps1 -ClientId $($app.AppId) -TenantId $tenant ..."
    Write-Host '  AppId ani TenantId nezapisujte do repozitáře.'
}
finally {
    if ($ownsConnection) { Disconnect-MgGraph | Out-Null }
}
