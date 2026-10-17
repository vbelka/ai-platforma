<#
.SYNOPSIS
    WS0 audit: nastavení sdílení SharePoint Online a OneDrive na úrovni tenantu a jednotlivých webů.

.DESCRIPTION
    REŽIM: POUZE ČTENÍ. Skript volá jen Get-SPOTenant a Get-SPOSite. Nic nemění.
    Spouští výhradně administrátor (člověk).

    Dopad na tenant: žádný. (Connect-SPOService jen naváže relaci správce.)

    Požadavky:
      - Modul Microsoft.Online.SharePoint.PowerShell (SharePoint Online Management Shell).
        Doporučeno spouštět ve Windows PowerShell 5.1. V PowerShell 7 skript modul importuje
        s -UseWindowsPowerShell (podle dokumentace Microsoft).
      - Role: SharePoint Administrator (nebo Global Administrator).
        Pozn.: Global Reader k Connect-SPOService nestačí.

    Co skript zjišťuje:
      - Tenant: SharingCapability, OneDriveSharingCapability (povolení odkazů „Kdokoli“),
        výchozí typ/rozsah odkazu (DefaultSharingLinkType, CoreDefaultShareLinkScope,
        OneDriveDefaultShareLinkScope), expirace anonymních odkazů, oprávnění anonymních odkazů,
        omezení domén, zobrazení deklarací „Everyone“ / „Everyone except external users“ (sdílení celé organizaci).
      - Weby: úroveň sdílení každého webu (vč. OneDrive s -IncludeOneDrive), výchozí typ odkazu,
        citlivostní popisek, propojení s týmem.
        Pozor: Get-SPOSite s -Limit nevyplňuje SharingCapability a další vlastnosti sdílení
        (poznámka v dokumentaci), proto skript čte každý web zvlášť přes -Identity. U velkých tenantů
        to trvá dlouho – lze vypnout přepínačem -SkipSiteDetail.

    Výstupy:
      sharing-tenant.csv   vybraná nastavení tenantu + hodnocení rizika
      sharing-sites.csv    weby a jejich úroveň sdílení
      sharing-summary.json souhrn

    Ověřeno (zdroj Microsoft Learn, 2026-10-13):
      https://learn.microsoft.com/powershell/module/microsoft.online.sharepoint.powershell/get-spotenant
      https://learn.microsoft.com/powershell/module/microsoft.online.sharepoint.powershell/set-spotenant  (význam hodnot)
      https://learn.microsoft.com/powershell/module/microsoft.online.sharepoint.powershell/get-sposite
      https://learn.microsoft.com/powershell/module/microsoft.online.sharepoint.powershell/connect-sposervice
      https://learn.microsoft.com/powershell/sharepoint/sharepoint-online/connect-sharepoint-online

.PARAMETER AdminUrl
    URL centra pro správu SharePoint, např. https://contoso-admin.sharepoint.com. Neukládat do repozitáře.

.PARAMETER IncludeOneDrive
    Zahrne i weby OneDrive (osobní weby). U větších organizací výrazně prodlouží běh.

.PARAMETER SkipSiteDetail
    Nečte weby jednotlivě (rychlé, ale bez úrovně sdílení webů).

.PARAMETER OutputPath
    Cílová složka. Výchozí <repo>/reports/<yyyy-MM-dd>_WS0 (mimo Git).

.EXAMPLE
    .\Get-WS0SharingSettingsReport.ps1 -AdminUrl https://contoso-admin.sharepoint.com -IncludeOneDrive
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^https://[a-zA-Z0-9-]+-admin\.sharepoint\.(com|us|de|cn)/?$')]
    [string]$AdminUrl,
    [switch]$IncludeOneDrive,
    [switch]$SkipSiteDetail,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AuditCommon.psm1') -Force
Assert-AuditModule -Name 'Microsoft.Online.SharePoint.PowerShell'

if ($PSVersionTable.PSEdition -eq 'Core') {
    Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell -WarningAction SilentlyContinue
}
else {
    Import-Module Microsoft.Online.SharePoint.PowerShell -DisableNameChecking
}

Connect-SPOService -Url $AdminUrl

$folder = Get-AuditOutputFolder -OutputPath $OutputPath
Write-Host "WS0 sdílení SPO/OneDrive – výstupy: $folder"

# --- 1) Tenant settings -------------------------------------------------------------------
$tenant = Get-SPOTenant

function Get-SharingRisk([string]$capability) {
    switch ($capability) {
        'ExternalUserAndGuestSharing'     { 'VYSOKÉ – povoleny odkazy „Kdokoli“ (anonymní)' }
        'ExternalUserSharingOnly'         { 'STŘEDNÍ – noví i stávající hosté' }
        'ExistingExternalUserSharingOnly' { 'NÍZKÉ – jen stávající hosté' }
        'Disabled'                        { 'NEJNIŽŠÍ – jen interní' }
        default                           { 'NEZNÁMÉ' }
    }
}

$tenantProps = 'SharingCapability', 'OneDriveSharingCapability', 'DefaultSharingLinkType', 'DefaultLinkPermission',
'CoreDefaultShareLinkScope', 'OneDriveDefaultShareLinkScope', 'RequireAnonymousLinksExpireInDays',
'FileAnonymousLinkType', 'FolderAnonymousLinkType', 'SharingDomainRestrictionMode', 'PreventExternalUsersFromResharing',
'ExternalUserExpirationRequired', 'ExternalUserExpireInDays', 'ShowEveryoneClaim', 'ShowEveryoneExceptExternalUsersClaim',
'ShowAllUsersClaim', 'EnableRestrictedAccessControl'

$tenantRows = foreach ($name in $tenantProps) {
    $value = if ($tenant.PSObject.Properties[$name]) { $tenant.$name } else { '(vlastnost není ve verzi modulu)' }
    $risk = switch ($name) {
        'SharingCapability'         { Get-SharingRisk "$value" }
        'OneDriveSharingCapability' { Get-SharingRisk "$value" }
        'DefaultSharingLinkType'    { if ("$value" -in 'AnonymousAccess', 'None') { 'VYSOKÉ – výchozí odkaz může být „Kdokoli“' } elseif ("$value" -eq 'Internal') { 'STŘEDNÍ – výchozí odkaz pro celou organizaci' } else { '' } }
        'CoreDefaultShareLinkScope' { if ("$value" -eq 'Anyone') { 'VYSOKÉ' } elseif ("$value" -eq 'Organization') { 'STŘEDNÍ – výchozí odkaz pro celou organizaci' } else { '' } }
        'OneDriveDefaultShareLinkScope' { if ("$value" -eq 'Anyone') { 'VYSOKÉ' } elseif ("$value" -eq 'Organization') { 'STŘEDNÍ – výchozí odkaz pro celou organizaci' } else { '' } }
        'RequireAnonymousLinksExpireInDays' { $days = 0; if (-not [int]::TryParse("$value", [ref]$days) -or $days -le 0) { 'Anonymní odkazy bez expirace' } else { '' } }
        'ShowEveryoneExceptExternalUsersClaim' { if ("$value" -eq 'True') { 'Lze sdílet „Všem kromě externích“ (celá organizace)' } else { '' } }
        'ShowEveryoneClaim'         { if ("$value" -eq 'True') { 'Lze sdílet „Všem“ vč. hostů' } else { '' } }
        default { '' }
    }
    [pscustomobject]@{ Setting = $name; Value = "$value"; Risk = $risk }
}
Export-AuditCsv -InputObject @($tenantRows) -Folder $folder -FileName 'sharing-tenant.csv'

# --- 2) Sites -----------------------------------------------------------------------------
$siteList = @(Get-SPOSite -Limit All -IncludePersonalSite:$IncludeOneDrive.IsPresent)
Write-Host ("  Nalezeno webů: {0}" -f $siteList.Count)

$siteRows = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($s in $siteList) {
    $i++
    $detail = $s
    if (-not $SkipSiteDetail) {
        Write-Progress -Activity 'Čtení nastavení sdílení webů' -Status $s.Url -PercentComplete (100 * $i / [math]::Max(1, $siteList.Count))
        try { $detail = Get-SPOSite -Identity $s.Url }
        catch { Write-Warning "Web $($s.Url) nelze načíst: $($_.Exception.Message)" }
    }

    $siteRows.Add([pscustomobject]@{
            Url                          = $s.Url
            Title                        = $s.Title
            Template                     = $s.Template
            Owner                        = $s.Owner
            IsOneDrive                   = ($s.Url -match '-my\.sharepoint\.')
            IsTeamsConnected             = $s.IsTeamsConnected
            GroupId                      = $s.GroupId
            SharingCapability            = if ($SkipSiteDetail) { '(nenačteno)' } else { $detail.SharingCapability }
            SharingRisk                  = if ($SkipSiteDetail) { '' } else { Get-SharingRisk "$($detail.SharingCapability)" }
            DefaultSharingLinkType       = if ($SkipSiteDetail) { '' } else { $detail.DefaultSharingLinkType }
            DefaultLinkPermission        = if ($SkipSiteDetail) { '' } else { $detail.DefaultLinkPermission }
            AnonymousLinkExpirationInDays = if ($SkipSiteDetail) { '' } else { $detail.AnonymousLinkExpirationInDays }
            SensitivityLabel             = if ($SkipSiteDetail) { '' } else { $detail.SensitivityLabel }
            LockState                    = $s.LockState
            LastContentModifiedDate      = $s.LastContentModifiedDate
            StorageUsageCurrentMB        = $s.StorageUsageCurrent
        })
}
Write-Progress -Activity 'Čtení nastavení sdílení webů' -Completed
Export-AuditCsv -InputObject $siteRows.ToArray() -Folder $folder -FileName 'sharing-sites.csv'

# --- 3) Summary ---------------------------------------------------------------------------
$summary = [ordered]@{
    GeneratedAt                   = (Get-Date).ToString('s')
    TenantSharingCapability       = "$($tenant.SharingCapability)"
    OneDriveSharingCapability     = "$($tenant.OneDriveSharingCapability)"
    AnyoneLinksAllowedAtTenant    = ("$($tenant.SharingCapability)" -eq 'ExternalUserAndGuestSharing')
    SitesTotal                    = $siteRows.Count
    SitesAllowingAnyoneLinks      = @($siteRows | Where-Object { "$($_.SharingCapability)" -eq 'ExternalUserAndGuestSharing' }).Count
    SitesWithoutSensitivityLabel  = if ($SkipSiteDetail) { $null } else { @($siteRows | Where-Object { -not $_.SensitivityLabel -and -not $_.IsOneDrive }).Count }
    OneDriveIncluded              = [bool]$IncludeOneDrive
    SiteDetailRead                = -not $SkipSiteDetail
}
Export-AuditJson -InputObject $summary -Folder $folder -FileName 'sharing-summary.json'

Disconnect-SPOService
Write-Host 'Hotovo. Nic nebylo změněno.'
