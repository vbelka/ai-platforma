<#
.SYNOPSIS
    WS0 audit jedním příkazem: spustí všech 5 auditních skriptů a vytvoří souhrnnou zprávu.

.DESCRIPTION
    REŽIM: POUZE ČTENÍ. Orchestrátor jen volá auditní skripty WS0 (všechny pouze čtou) a skript
    New-WS0Summary.ps1 (pracuje jen s lokálními soubory). Nic v tenantu nemění.
    Spouští výhradně administrátor (člověk), nikdy ne Claude.

    Průběh:
      1. Jedno přihlášení k Microsoft Graph se všemi potřebnými oprávněními (jen čtení).
      2. Licence → MFA → veřejné skupiny (sdílí přihlášení z kroku 1).
      3. Nastavení sdílení SharePoint/OneDrive (vlastní přihlášení k SharePoint admin center).
      4. Odkazy „Kdokoli“ / celá organizace z auditního logu (vlastní přihlášení k Exchange Online).
      5. Souhrnná zpráva WS0-souhrn.md.
    Selhání jednoho kroku nezastaví ostatní; stav kroků je v run-log.json.

    Dopad na tenant: žádný. Při prvním přihlášení ke Graphu může Entra ID vyžádat souhlas (consent)
    – viz scripts/audit/README.md, kap. 3.

    Požadavky: PowerShell 7 na Windows (krok SharePoint používá import modulu s -UseWindowsPowerShell).

.PARAMETER AdminUrl
    URL SharePoint admin center, např. https://contoso-admin.sharepoint.com. Bez něj se krok SharePoint přeskočí.

.PARAMETER UserPrincipalName
    UPN správce – předvyplní přihlášení k Exchange Online.

.PARAMETER ClientId
    Volitelné. AppId vlastní auditní aplikace (scripts/identity/New-WS0AuditApp.ps1). Bez něj se použije
    Microsoft Graph Command Line Tools. Neukládat do repozitáře.

.PARAMETER TenantId
    Volitelné. Doména tenantu klienta. Neukládat do repozitáře.

.PARAMETER Days
    Období auditního logu ve dnech. Výchozí 90.

.PARAMETER IncludeSignInActivity
    Poslední přihlášení uživatelů (vyžaduje Entra ID P1/P2).

.PARAMETER IncludeOneDrive
    Zahrne weby OneDrive do auditu sdílení.

.PARAMETER Skip
    Kroky, které se mají vynechat: License, Mfa, Groups, SharingSettings, SharingLinks.

.PARAMETER OutputPath
    Cílová složka. Výchozí <repo>/reports/<yyyy-MM-dd>_WS0 (mimo Git).

.EXAMPLE
    .\Invoke-WS0Audit.ps1 -AdminUrl https://contoso-admin.sharepoint.com -UserPrincipalName admin@contoso.onmicrosoft.com -IncludeSignInActivity
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Parameters are used inside step scriptblocks.')]
[CmdletBinding()]
param(
    [ValidatePattern('^https://[a-zA-Z0-9-]+-admin\.sharepoint\.(com|us|de|cn)/?$')]
    [string]$AdminUrl,
    [string]$UserPrincipalName,
    [string]$TenantId,
    [string]$ClientId,
    [ValidateRange(1, 365)] [int]$Days = 90,
    [switch]$IncludeSignInActivity,
    [switch]$IncludeOneDrive,
    [ValidateSet('License', 'Mfa', 'Groups', 'SharingSettings', 'SharingLinks')]
    [string[]]$Skip = @(),
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AuditCommon.psm1') -Force

$folder = Get-AuditOutputFolder -OutputPath $OutputPath
Write-Host "=== WS0 audit – výstupy: $folder ===" -ForegroundColor Cyan

$runLog = New-Object System.Collections.Generic.List[object]

function Invoke-AuditStep {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [scriptblock]$Action
    )

    if ($Skip -contains $Name) {
        $runLog.Add([pscustomobject]@{ Step = $Name; Status = 'Skipped'; Error = $null; DurationSec = 0 })
        Write-Host "--- ${Name}: přeskočeno" -ForegroundColor DarkGray
        return
    }

    Write-Host "--- $Name" -ForegroundColor Cyan
    $started = Get-Date
    try {
        & $Action
        $runLog.Add([pscustomobject]@{ Step = $Name; Status = 'OK'; Error = $null; DurationSec = [int]((Get-Date) - $started).TotalSeconds })
    }
    catch {
        Write-Warning "Krok $Name selhal: $($_.Exception.Message)"
        $runLog.Add([pscustomobject]@{ Step = $Name; Status = 'Failed'; Error = $_.Exception.Message; DurationSec = [int]((Get-Date) - $started).TotalSeconds })
    }
}

# --- 1) One Graph sign-in for all Graph-based steps --------------------------------------------
$graphSteps = @('License', 'Mfa', 'Groups') | Where-Object { $Skip -notcontains $_ }
$ownsGraph = $false
if ($graphSteps) {
    Assert-AuditModule -Name 'Microsoft.Graph.Authentication'
    $scopes = @('LicenseAssignment.Read.All', 'User.Read.All', 'AuditLog.Read.All', 'Policy.Read.All', 'Group.Read.All')
    $ownsGraph = Connect-AuditGraph -Scopes $scopes -TenantId $TenantId -ClientId $ClientId
}

Invoke-AuditStep -Name 'License' -Action {
    & (Join-Path $PSScriptRoot 'Get-WS0LicenseReport.ps1') -OutputPath $folder -TenantId $TenantId -ClientId $ClientId -IncludeSignInActivity:$IncludeSignInActivity
}
Invoke-AuditStep -Name 'Mfa' -Action {
    & (Join-Path $PSScriptRoot 'Get-WS0MfaReport.ps1') -OutputPath $folder -TenantId $TenantId -ClientId $ClientId
}
Invoke-AuditStep -Name 'Groups' -Action {
    & (Join-Path $PSScriptRoot 'Get-WS0PublicGroupsReport.ps1') -OutputPath $folder -TenantId $TenantId -ClientId $ClientId
}

if ($ownsGraph) { Disconnect-MgGraph | Out-Null }

# --- 2) SharePoint / OneDrive sharing settings -------------------------------------------------
if (-not $AdminUrl -and $Skip -notcontains 'SharingSettings') {
    Write-Warning 'Není zadán -AdminUrl – krok SharingSettings se přeskočí.'
    $Skip += 'SharingSettings'
}
Invoke-AuditStep -Name 'SharingSettings' -Action {
    & (Join-Path $PSScriptRoot 'Get-WS0SharingSettingsReport.ps1') -AdminUrl $AdminUrl -OutputPath $folder -IncludeOneDrive:$IncludeOneDrive
}

# --- 3) Anyone / organization links from the audit log -----------------------------------------
Invoke-AuditStep -Name 'SharingLinks' -Action {
    $linkParams = @{ OutputPath = $folder; Days = $Days }
    if ($UserPrincipalName) { $linkParams.UserPrincipalName = $UserPrincipalName }
    & (Join-Path $PSScriptRoot 'Get-WS0SharingLinksReport.ps1') @linkParams
}

# --- 4) Run log + summary report -----------------------------------------------------------------
Export-AuditJson -InputObject ([ordered]@{
        GeneratedAt = (Get-Date).ToString('s')
        Steps       = $runLog.ToArray()
    }) -Folder $folder -FileName 'run-log.json'

& (Join-Path $PSScriptRoot 'New-WS0Summary.ps1') -ReportFolder $folder

Write-Host ''
$runLog | Format-Table Step, Status, DurationSec, Error -AutoSize | Out-Host
Write-Host "Hotovo. Nic nebylo změněno. Zpráva: $(Join-Path $folder 'WS0-souhrn.md')" -ForegroundColor Green
