<#
.SYNOPSIS
    WS0 audit: veřejné týmy a veřejné skupiny Microsoft 365 (obsah dostupný komukoli v organizaci).

.DESCRIPTION
    REŽIM: POUZE ČTENÍ. Skript používá jen Get-* cmdlety Microsoft Graph. Nic nemění.
    Spouští výhradně administrátor (člověk).

    Proč je to důležité pro AI: Microsoft 365 Copilot zpřístupní uživateli obsah, ke kterému má
    oprávnění. Veřejný tým / skupina = jeho web SharePoint je čitelný pro všechny členy organizace,
    takže se obsah může objevit v odpovědích Copilota komukoli. (Tvrzení ověřit při WS0 na Learn –
    viz checklist WS0, bod Oversharing.)

    Dopad na tenant: žádný. Možná výzva k souhlasu (consent) aplikace Microsoft Graph Command Line Tools.

    Oprávnění Graph (delegovaná, jen čtení): Group.Read.All
      (Learn uvádí jako „least privileged“ Group-NestingSupport.ReadWrite.All, což je zápisové oprávnění –
       záměrně používáme čtecí Group.Read.All ze seznamu „higher privileged“.)
    Doporučená role: Global Reader.

    Výstupy:
      groups-m365.csv          všechny skupiny Microsoft 365: viditelnost, zda je to tým, počet vlastníků
      groups-public.csv        jen veřejné (Public) – k revizi
      groups-summary.json      souhrn

    Ověřeno (zdroj Microsoft Learn, 2026-10-13):
      https://learn.microsoft.com/graph/api/group-list
      https://learn.microsoft.com/graph/api/resources/group  (visibility, resourceProvisioningOptions, groupTypes)
      https://learn.microsoft.com/powershell/module/microsoft.graph.groups/get-mggroup
      Alternativa přes modul MicrosoftTeams: Get-Team -Visibility Public
      https://learn.microsoft.com/powershell/module/microsoftteams/get-team

.PARAMETER OutputPath
    Cílová složka. Výchozí <repo>/reports/<yyyy-MM-dd>_WS0 (mimo Git).

.PARAMETER ClientId
    Volitelné. AppId vlastní auditní aplikace (scripts/identity/New-WS0AuditApp.ps1). Bez něj se použije
    Microsoft Graph Command Line Tools. Neukládat do repozitáře.

.PARAMETER TenantId
    Volitelné. Doména tenantu. Neukládat do repozitáře.

.PARAMETER SkipOwners
    Nezjišťuje počet vlastníků (rychlejší u stovek skupin).

.EXAMPLE
    .\Get-WS0PublicGroupsReport.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$TenantId,
    [string]$ClientId,
    [switch]$SkipOwners
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AuditCommon.psm1') -Force
Assert-AuditModule -Name 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Groups'

$ownsConnection = Connect-AuditGraph -Scopes @('Group.Read.All') -TenantId $TenantId -ClientId $ClientId

$folder = Get-AuditOutputFolder -OutputPath $OutputPath
Write-Host "WS0 veřejné týmy/skupiny – výstupy: $folder"

$groups = @(Get-MgGroup -All -Filter "groupTypes/any(c:c eq 'Unified')" `
        -Property 'id', 'displayName', 'mail', 'visibility', 'resourceProvisioningOptions', 'createdDateTime', 'description')

$rows = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($g in $groups) {
    $i++
    $ownerCount = $null
    if (-not $SkipOwners) {
        Write-Progress -Activity 'Čtení vlastníků skupin' -Status $g.DisplayName -PercentComplete (100 * $i / [math]::Max(1, $groups.Count))
        $ownerCount = @(Get-MgGroupOwner -GroupId $g.Id -All).Count
    }

    $rows.Add([pscustomobject]@{
            DisplayName     = $g.DisplayName
            Mail            = $g.Mail
            Visibility      = $g.Visibility
            IsTeam          = (@($g.ResourceProvisioningOptions) -contains 'Team')
            OwnerCount      = $ownerCount
            FlagNoOwner     = ($null -ne $ownerCount -and $ownerCount -eq 0)
            CreatedDateTime = $g.CreatedDateTime
            GroupId         = $g.Id
        })
}
Write-Progress -Activity 'Čtení vlastníků skupin' -Completed

$public = @($rows | Where-Object { $_.Visibility -eq 'Public' })
Export-AuditCsv -InputObject $rows.ToArray() -Folder $folder -FileName 'groups-m365.csv'
Export-AuditCsv -InputObject $public -Folder $folder -FileName 'groups-public.csv'

$summary = [ordered]@{
    GeneratedAt          = (Get-Date).ToString('s')
    M365GroupsTotal      = $rows.Count
    TeamsTotal           = @($rows | Where-Object IsTeam).Count
    PublicGroups         = $public.Count
    PublicTeams          = @($public | Where-Object IsTeam).Count
    GroupsWithoutOwner   = if ($SkipOwners) { $null } else { @($rows | Where-Object FlagNoOwner).Count }
}
Export-AuditJson -InputObject $summary -Folder $folder -FileName 'groups-summary.json'

if ($ownsConnection) { Disconnect-MgGraph | Out-Null }
Write-Host 'Hotovo. Nic nebylo změněno.'
