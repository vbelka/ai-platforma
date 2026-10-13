<#
.SYNOPSIS
    WS0 audit: vytvořené a použité odkazy „Kdokoli“ (anonymní) a odkazy pro celou organizaci – z auditního logu.

.DESCRIPTION
    REŽIM: POUZE ČTENÍ. Skript volá Get-AdminAuditLogConfig a Search-UnifiedAuditLog. Nic nemění.
    Spouští výhradně administrátor (člověk).

    Dopad na tenant: žádný. Pokud je sjednocený auditní log vypnutý, skript to jen nahlásí – NEZAPÍNÁ ho.

    Omezení metody:
      - Auditní log zachycuje události za dobu uchování (podle licence; standardně řádově 180 dní –
        K OVĚŘENÍ na Learn pro konkrétní licenci klienta). Odkazy vytvořené dříve skript nenajde.
        Pro úplný inventář existujících odkazů použít v SharePoint admin center reporty
        „Data access governance“ (SharePoint Advanced Management – licenční podmínky K OVĚŘENÍ).
      - Search-UnifiedAuditLog vrací v jedné relaci ReturnLargeSet max. 50 000 záznamů;
        skript proto hledá po jednotlivých operacích a po dnech (-ChunkDays).

    Sledované operace (výchozí):
      AnonymousLinkCreated, AnonymousLinkUpdated, AnonymousLinkUsed – odkazy „Kdokoli“
      CompanyLinkCreated, CompanyLinkUsed                              – odkazy „Lidé ve vaší organizaci“
        (názvy Company* K OVĚŘENÍ v seznamu aktivit auditu na Learn; neplatná operace jen vrátí 0 záznamů)

    Požadavky:
      - Modul ExchangeOnlineManagement.
      - Role: View-Only Audit Logs nebo Audit Logs (Exchange Online / Purview), např. přes skupinu
        rolí Compliance Management nebo Organization Management.

    Výstupy:
      links-audit-events.csv     jednotlivé události (čas, operace, uživatel, soubor, web, IP)
      links-audit-by-site.csv    souhrn podle webu a operace
      links-audit-summary.json   souhrn vč. stavu auditního logu

    Ověřeno (zdroj Microsoft Learn, 2026-10-13):
      https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog
      https://learn.microsoft.com/powershell/module/exchangepowershell/set-adminauditlogconfig  (UnifiedAuditLogIngestionEnabled)
      https://learn.microsoft.com/powershell/module/exchangepowershell/connect-exchangeonline
      https://learn.microsoft.com/purview/audit-log-sharing  (AnonymousLinkCreated/Used, SecureLinkCreated, SharingSet)

.PARAMETER Days
    Kolik dní zpět hledat. Výchozí 90.

.PARAMETER ChunkDays
    Délka jednoho dotazovacího okna ve dnech. Výchozí 7. Snižte u velkých tenantů.

.PARAMETER Operations
    Seznam operací auditního logu.

.PARAMETER UserPrincipalName
    UPN správce pro přihlášení do Exchange Online (předvyplní přihlašovací okno).

.PARAMETER OutputPath
    Cílová složka. Výchozí <repo>/reports/<yyyy-MM-dd>_WS0 (mimo Git).

.EXAMPLE
    .\Get-WS0SharingLinksReport.ps1 -UserPrincipalName admin@contoso.onmicrosoft.com -Days 90
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 365)] [int]$Days = 90,
    [ValidateRange(1, 31)] [int]$ChunkDays = 7,
    [string[]]$Operations = @('AnonymousLinkCreated', 'AnonymousLinkUpdated', 'AnonymousLinkUsed', 'CompanyLinkCreated', 'CompanyLinkUsed'),
    [string]$UserPrincipalName,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AuditCommon.psm1') -Force
Assert-AuditModule -Name 'ExchangeOnlineManagement'

$connectParams = @{ ShowBanner = $false }
if ($UserPrincipalName) { $connectParams.UserPrincipalName = $UserPrincipalName }
Connect-ExchangeOnline @connectParams

$folder = Get-AuditOutputFolder -OutputPath $OutputPath
Write-Host "WS0 odkazy Kdokoli / celá organizace – výstupy: $folder"

# --- 1) Audit log state (read only) ----------------------------------------------------------
$auditEnabled = $null
try { $auditEnabled = (Get-AdminAuditLogConfig).UnifiedAuditLogIngestionEnabled }
catch { Write-Warning "Stav auditního logu nelze zjistit: $($_.Exception.Message)" }
if ($auditEnabled -eq $false) {
    Write-Warning 'Sjednocený auditní log je VYPNUTÝ. Výsledky budou prázdné. Zapnutí je změna tenantu – řeší checklist WS0, ne tento skript.'
}

# --- 2) Search in windows ---------------------------------------------------------------------
$end = (Get-Date).ToUniversalTime()
$start = $end.AddDays(-$Days)
$events = New-Object System.Collections.Generic.List[object]
$seen = New-Object 'System.Collections.Generic.HashSet[string]'

foreach ($operation in $Operations) {
    $windowStart = $start
    while ($windowStart -lt $end) {
        $windowEnd = $windowStart.AddDays($ChunkDays)
        if ($windowEnd -gt $end) { $windowEnd = $end }
        $sessionId = [guid]::NewGuid().ToString()
        Write-Host ("  {0}: {1:yyyy-MM-dd} – {2:yyyy-MM-dd}" -f $operation, $windowStart, $windowEnd)

        $windowCount = 0
        do {
            $page = @(Search-UnifiedAuditLog -StartDate $windowStart -EndDate $windowEnd -Operations $operation `
                    -SessionId $sessionId -SessionCommand ReturnLargeSet -ResultSize 5000)
            foreach ($record in $page) {
                if (-not $seen.Add([string]$record.Identity)) { continue }   # ReturnLargeSet is unsorted; dedupe
                $windowCount++
                $data = $record.AuditData | ConvertFrom-Json
                $events.Add([pscustomobject]@{
                        CreationTimeUtc = $data.CreationTime
                        Operation       = $record.Operations
                        UserId          = $record.UserIds
                        SiteUrl         = $data.SiteUrl
                        ObjectId        = $data.ObjectId
                        SourceFileName  = $data.SourceFileName
                        ItemType        = $data.ItemType
                        EventData       = $data.EventData
                        ClientIP        = $data.ClientIP
                    })
            }
        } while ($page.Count -gt 0 -and $windowCount -lt 50000)

        if ($windowCount -ge 50000) {
            Write-Warning "Okno $operation $windowStart dosáhlo limitu 50 000 záznamů – spusťte znovu s menším -ChunkDays."
        }
        $windowStart = $windowEnd
    }
}

$eventRows = @($events | Sort-Object CreationTimeUtc)
Export-AuditCsv -InputObject $eventRows -Folder $folder -FileName 'links-audit-events.csv'

$bySite = @($eventRows | Group-Object SiteUrl, Operation | ForEach-Object {
        [pscustomobject]@{
            SiteUrl     = $_.Group[0].SiteUrl
            Operation   = $_.Group[0].Operation
            Count       = $_.Count
            UniqueUsers = @($_.Group.UserId | Sort-Object -Unique).Count
            LastEvent   = ($_.Group.CreationTimeUtc | Sort-Object | Select-Object -Last 1)
        }
    } | Sort-Object Count -Descending)
Export-AuditCsv -InputObject $bySite -Folder $folder -FileName 'links-audit-by-site.csv'

$summary = [ordered]@{
    GeneratedAt          = (Get-Date).ToString('s')
    PeriodStartUtc       = $start.ToString('s')
    PeriodEndUtc         = $end.ToString('s')
    UnifiedAuditEnabled  = $auditEnabled
    EventsTotal          = $eventRows.Count
    ByOperation          = [ordered]@{}
    SitesWithAnyoneLinks = @($eventRows | Where-Object { $_.Operation -like 'AnonymousLink*' } | Select-Object -ExpandProperty SiteUrl -Unique).Count
}
foreach ($op in $Operations) { $summary.ByOperation[$op] = @($eventRows | Where-Object Operation -eq $op).Count }
Export-AuditJson -InputObject $summary -Folder $folder -FileName 'links-audit-summary.json'

Disconnect-ExchangeOnline -Confirm:$false
Write-Host 'Hotovo. Nic nebylo změněno.'
