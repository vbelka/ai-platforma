<#
.SYNOPSIS
    WS0: vytvoří souhrnnou zprávu WS0-souhrn.md z výstupů auditních skriptů.

.DESCRIPTION
    REŽIM: BEZ PŘÍSTUPU K TENANTU. Skript čte jen lokální soubory *-summary.json a CSV ve složce
    s výstupy a zapisuje WS0-souhrn.md do téže složky. Nepřipojuje se k Microsoft 365.

    Nálezy jsou rozděleny podle závažnosti (Kritické / Vysoké / Střední / Nízké). Pravidla
    hodnocení jsou v tomto skriptu (funkce Add-Finding) a odpovídají checklistu
    checklists/WS0-vychozi-audit.md. Zpráva je podklad – závěry potvrzuje auditor.

    Zpráva obsahuje jen agregovaná čísla a názvy webů/skupin, ne seznamy uživatelů.
    Přesto patří do /reports (mimo Git).

.PARAMETER ReportFolder
    Složka s výstupy WS0 (např. reports/2026-10-17_WS0).

.EXAMPLE
    .\New-WS0Summary.ps1 -ReportFolder ..\..\reports\2026-10-17_WS0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$ReportFolder
)

$ErrorActionPreference = 'Stop'
$ReportFolder = (Resolve-Path $ReportFolder).Path

function Read-AuditJson([string]$FileName) {
    $path = Join-Path $ReportFolder $FileName
    if (Test-Path $path) { Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
}

function Read-AuditCsv([string]$FileName) {
    $path = Join-Path $ReportFolder $FileName
    if (-not (Test-Path $path)) { return $null }
    $first = Get-Content $path -TotalCount 1 -Encoding UTF8
    if ($first -match '^﻿?#') { return @() }   # empty-result marker written by Export-AuditCsv
    @(Import-Csv $path -Delimiter ';' -Encoding UTF8)
}

$findings = New-Object System.Collections.Generic.List[object]
function Add-Finding([string]$Severity, [string]$Area, [string]$Text, [string]$Checklist) {
    $findings.Add([pscustomobject]@{ Severity = $Severity; Area = $Area; Text = $Text; Checklist = $Checklist })
}

$lic = Read-AuditJson 'licenses-summary.json'
$mfa = Read-AuditJson 'mfa-summary.json'
$grp = Read-AuditJson 'groups-summary.json'
$shr = Read-AuditJson 'sharing-summary.json'
$lnk = Read-AuditJson 'links-audit-summary.json'
$run = Read-AuditJson 'run-log.json'
$skus = Read-AuditCsv 'licenses-skus.csv'
$tenantSharing = Read-AuditCsv 'sharing-tenant.csv'
$publicGroups = Read-AuditCsv 'groups-public.csv'
$linksBySite = Read-AuditCsv 'links-audit-by-site.csv'

# --- Rules ---------------------------------------------------------------------------------------
if ($mfa) {
    if ($mfa.AdminsWithoutMfa -gt 0) {
        Add-Finding 'Kritické' 'MFA' "Správci bez schopnosti MFA: $($mfa.AdminsWithoutMfa) (mfa-admins-without-mfa.csv)." 'C2'
    }
    if (-not $mfa.SecurityDefaultsEnabled -and $mfa.ConditionalAccessEnabledMfa -eq 0) {
        Add-Finding 'Kritické' 'MFA' 'MFA není vynuceno: výchozí zabezpečení je vypnuté a žádná zapnutá zásada podmíněného přístupu nevyžaduje MFA. Ověřit per-user MFA ručně.' 'C4, C6'
    }
    if ($mfa.MembersNotMfaCapable -gt 0) {
        Add-Finding 'Vysoké' 'MFA' "Členové bez zaregistrované MFA metody: $($mfa.MembersNotMfaCapable) z $($mfa.MembersTotal)." 'C3'
    }
    if ($mfa.ConditionalAccessReadError) {
        Add-Finding 'Nízké' 'MFA' "Zásady podmíněného přístupu nešlo načíst (pravděpodobně bez Entra ID P1): $($mfa.ConditionalAccessReadError)" 'B4'
    }
}

if ($lnk) {
    if ($lnk.UnifiedAuditEnabled -eq $false) {
        Add-Finding 'Kritické' 'Audit' 'Sjednocený auditní log je vypnutý – nelze dohledat sdílení ani incidenty.' 'E1'
    }
    $anyCreated = [int]$lnk.ByOperation.AnonymousLinkCreated
    if ($anyCreated -gt 0) {
        Add-Finding 'Vysoké' 'Sdílení' ('Za sledované období vzniklo {0} odkazů „Kdokoli“ na {1} webech (links-audit-by-site.csv).' -f $anyCreated, $lnk.SitesWithAnyoneLinks) 'E3'
    }
    $orgCreated = [int]$lnk.ByOperation.CompanyLinkCreated
    if ($orgCreated -gt 0) {
        Add-Finding 'Střední' 'Sdílení' "Za sledované období vzniklo $orgCreated odkazů pro celou organizaci." 'E4'
    }
}

if ($tenantSharing) {
    foreach ($row in $tenantSharing | Where-Object { $_.Risk }) {
        $severity = if ($row.Risk -like 'VYSOKÉ*') { 'Vysoké' } elseif ($row.Risk -like 'STŘEDNÍ*' -or $row.Risk -like 'Lze sdílet*' -or $row.Risk -like 'Anonymní*') { 'Střední' } else { 'Nízké' }
        Add-Finding $severity 'Sdílení' "Tenant: $($row.Setting) = $($row.Value) – $($row.Risk)" 'D2–D5'
    }
}
if ($shr) {
    if ($shr.SitesAllowingAnyoneLinks -gt 0) {
        Add-Finding 'Vysoké' 'Sdílení' ('Weby s povolenými odkazy „Kdokoli“: {0} z {1} (sharing-sites.csv).' -f $shr.SitesAllowingAnyoneLinks, $shr.SitesTotal) 'D6'
    }
    if ($shr.SitesWithoutSensitivityLabel -gt 0) {
        Add-Finding 'Střední' 'Sdílení' "Weby SharePoint bez citlivostního popisku: $($shr.SitesWithoutSensitivityLabel)." 'D7'
    }
}

if ($grp) {
    if ($grp.PublicTeams -gt 0 -or $grp.PublicGroups -gt 0) {
        Add-Finding 'Vysoké' 'Týmy' "Veřejné skupiny M365: $($grp.PublicGroups), z toho týmů: $($grp.PublicTeams). Obsah je přístupný celé organizaci (groups-public.csv)." 'F2'
    }
    if ($grp.GroupsWithoutOwner -gt 0) {
        Add-Finding 'Střední' 'Týmy' "Skupiny M365 bez vlastníka: $($grp.GroupsWithoutOwner)." 'F4'
    }
}

if ($lic) {
    if ($lic.DisabledButLicensedCount -gt 0) {
        Add-Finding 'Nízké' 'Licence' "Zakázané účty s licencí: $($lic.DisabledButLicensedCount) – možná úspora." 'B6'
    }
    if ($lic.AssignmentErrorCount -gt 0) {
        Add-Finding 'Střední' 'Licence' "Chyby přiřazení licencí: $($lic.AssignmentErrorCount)." 'B6'
    }
    if (@($lic.SkusWithCopilotPlan).Count -eq 0) {
        Add-Finding 'Nízké' 'Licence' 'V tenantu nebyla nalezena SKU s plánem „COPILOT“ (heuristika – ověřit na Learn).' 'B3'
    }
}

if ($run) {
    foreach ($step in @($run.Steps) | Where-Object { $_.Status -eq 'Failed' }) {
        Add-Finding 'Vysoké' 'Audit' "Krok auditu $($step.Step) selhal: $($step.Error). Výsledky této oblasti chybí." 'A'
    }
}

# --- Markdown ------------------------------------------------------------------------------------
$order = @{ 'Kritické' = 0; 'Vysoké' = 1; 'Střední' = 2; 'Nízké' = 3 }
$sorted = @($findings | Sort-Object { $order[$_.Severity] }, Area)

$md = New-Object System.Text.StringBuilder
function Add-Line([string]$Text = '') { [void]$md.AppendLine($Text) }

Add-Line '# WS0 – souhrn výchozího auditu'
Add-Line ''
Add-Line "Vygenerováno: $((Get-Date).ToString('yyyy-MM-dd HH:mm')) · složka: ``$(Split-Path $ReportFolder -Leaf)``"
Add-Line ''
Add-Line '> Automaticky vytvořený podklad. Závěry, závažnost a doporučení potvrzuje auditor.'
Add-Line '> Obsahuje údaje o tenantu – ukládat jen do zabezpečeného úložiště, nikdy do Gitu.'
Add-Line ''
Add-Line '## Přehled nálezů'
Add-Line ''
Add-Line '| Závažnost | Počet |'
Add-Line '|---|---|'
foreach ($sev in 'Kritické', 'Vysoké', 'Střední', 'Nízké') {
    Add-Line "| $sev | $(@($sorted | Where-Object Severity -eq $sev).Count) |"
}
Add-Line ''
Add-Line '## Nálezy'
Add-Line ''
if ($sorted.Count -eq 0) {
    Add-Line 'Žádné automaticky zjištěné nálezy.'
}
else {
    Add-Line '| # | Závažnost | Oblast | Nález | Checklist WS0 |'
    Add-Line '|---|---|---|---|---|'
    $i = 0
    foreach ($f in $sorted) {
        $i++
        Add-Line "| $i | $($f.Severity) | $($f.Area) | $($f.Text -replace '\|', '/') | $($f.Checklist) |"
    }
}

Add-Line ''
Add-Line '## Klíčová čísla'
Add-Line ''
Add-Line '| Oblast | Ukazatel | Hodnota |'
Add-Line '|---|---|---|'
if ($lic) {
    Add-Line "| Licence | Uživatelé / s licencí / hosté | $($lic.UserCount) / $($lic.LicensedUserCount) / $($lic.GuestCount) |"
    Add-Line "| Licence | SKU s plánem COPILOT | $((@($lic.SkusWithCopilotPlan) -join ', ')) |"
}
if ($mfa) {
    Add-Line "| MFA | Členové schopní MFA | $($mfa.MembersMfaCapable) z $($mfa.MembersTotal) |"
    Add-Line "| MFA | Výchozí zabezpečení | $($mfa.SecurityDefaultsEnabled) |"
    Add-Line "| MFA | Zapnuté zásady CA vyžadující MFA | $($mfa.ConditionalAccessEnabledMfa) |"
}
if ($shr) {
    Add-Line "| Sdílení | SharePoint / OneDrive | $($shr.TenantSharingCapability) / $($shr.OneDriveSharingCapability) |"
    Add-Line "| Sdílení | Weby celkem / s odkazy Kdokoli | $($shr.SitesTotal) / $($shr.SitesAllowingAnyoneLinks) |"
}
if ($lnk) {
    $periodStart = ([datetime]$lnk.PeriodStartUtc).ToString('yyyy-MM-dd HH:mm')
    $periodEnd = ([datetime]$lnk.PeriodEndUtc).ToString('yyyy-MM-dd HH:mm')
    Add-Line "| Audit | Období | $periodStart – $periodEnd (UTC) |"
    Add-Line "| Audit | Události odkazů celkem | $($lnk.EventsTotal) |"
}
if ($grp) {
    Add-Line "| Týmy | Skupiny M365 / týmy / veřejné | $($grp.M365GroupsTotal) / $($grp.TeamsTotal) / $($grp.PublicGroups) |"
}

if ($skus -and $skus.Count -gt 0) {
    Add-Line ''
    Add-Line '## Licence (SKU)'
    Add-Line ''
    Add-Line '| SKU | Stav | Zakoupeno | Přiřazeno | Volné |'
    Add-Line '|---|---|---|---|---|'
    foreach ($s in $skus | Sort-Object { [int]$_.ConsumedUnits } -Descending) {
        Add-Line "| $($s.SkuPartNumber) | $($s.CapabilityStatus) | $($s.PrepaidEnabled) | $($s.ConsumedUnits) | $($s.AvailableUnits) |"
    }
}

if ($linksBySite -and $linksBySite.Count -gt 0) {
    Add-Line ''
    Add-Line '## Weby s nejvíce událostmi odkazů (top 10)'
    Add-Line ''
    Add-Line '| Web | Operace | Počet | Uživatelů |'
    Add-Line '|---|---|---|---|'
    foreach ($l in $linksBySite | Sort-Object { [int]$_.Count } -Descending | Select-Object -First 10) {
        Add-Line "| $($l.SiteUrl) | $($l.Operation) | $($l.Count) | $($l.UniqueUsers) |"
    }
}

if ($publicGroups -and $publicGroups.Count -gt 0) {
    Add-Line ''
    Add-Line '## Veřejné týmy a skupiny (k revizi vlastníky)'
    Add-Line ''
    Add-Line '| Název | Tým | Vlastníků |'
    Add-Line '|---|---|---|'
    foreach ($g in $publicGroups | Sort-Object DisplayName) {
        Add-Line "| $($g.DisplayName -replace '\|', '/') | $($g.IsTeam) | $($g.OwnerCount) |"
    }
}

$missing = @('licenses-summary.json', 'mfa-summary.json', 'groups-summary.json', 'sharing-summary.json', 'links-audit-summary.json') |
    Where-Object { -not (Test-Path (Join-Path $ReportFolder $_)) }
if ($missing) {
    Add-Line ''
    Add-Line '## Chybějící podklady'
    Add-Line ''
    foreach ($m in $missing) { Add-Line "- ``$m`` – příslušný skript neproběhl." }
}

$outPath = Join-Path $ReportFolder 'WS0-souhrn.md'
$encoding = if ($PSVersionTable.PSEdition -eq 'Core') { 'utf8BOM' } else { 'UTF8' }
Set-Content -Path $outPath -Value $md.ToString() -Encoding $encoding
Write-Host "  -> $outPath ($($sorted.Count) nálezů)"
