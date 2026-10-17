<#
.SYNOPSIS
    Offline tests of the WS0 audit scripts against stub modules with fictitious data.

.DESCRIPTION
    No connection to any tenant. Stub modules in tests/stubs replace Microsoft.Graph,
    Microsoft.Online.SharePoint.PowerShell and ExchangeOnlineManagement. Outputs go to a temp folder,
    never into /reports. Exit code = number of failed assertions.

    Run:  pwsh -NoProfile -File tests/Invoke-AuditTests.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Get-Item $PSScriptRoot).Parent.FullName
$auditDir = Join-Path (Join-Path $repoRoot 'scripts') 'audit'
$env:PSModulePath = (Join-Path $PSScriptRoot 'stubs') + [IO.Path]::PathSeparator + $env:PSModulePath

$script:Failures = 0
function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) { Write-Host "  [OK]   $Message" -ForegroundColor Green }
    else { Write-Host "  [FAIL] $Message" -ForegroundColor Red; $script:Failures++ }
}
function Read-Csv([string]$Folder, [string]$Name) { @(Import-Csv (Join-Path $Folder $Name) -Delimiter ';' -Encoding UTF8) }

$outDir = Join-Path ([IO.Path]::GetTempPath()) ("ws0-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $outDir | Out-Null

try {
    # --- Encoding: Windows PowerShell 5.1 needs a BOM to read UTF-8 scripts correctly --------------
    Write-Host 'Encoding'
    foreach ($file in Get-ChildItem $repoRoot -Recurse -Include *.ps1, *.psm1, *.psd1 -File) {
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        Assert-True $hasBom "UTF-8 BOM: $($file.FullName.Substring($repoRoot.Length + 1))"
    }

    # --- Smart double quotes end a double-quoted string in PowerShell (Czech text uses them) --------
    Write-Host 'Typografické uvozovky'
    $smartQuotes = @([char]0x201C, [char]0x201D, [char]0x201E)
    foreach ($file in Get-ChildItem $repoRoot -Recurse -Include *.ps1, *.psm1 -File) {
        $tokens = $null; $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
        $bad = @($tokens | Where-Object {
                $_.Kind -in 'StringExpandable', 'HereStringExpandable' -and $_.Text.IndexOfAny([char[]]$smartQuotes) -ge 0 })
        Assert-True ($bad.Count -eq 0 -and @($parseErrors).Count -eq 0) ('bez typografických uvozovek v řetězcích s dvojitými uvozovkami: ' + $file.Name)
    }

    # --- Full run via orchestrator -----------------------------------------------------------------
    Write-Host 'Invoke-WS0Audit (all steps)'
    & (Join-Path $auditDir 'Invoke-WS0Audit.ps1') -AdminUrl 'https://fiktivni-admin.sharepoint.com' `
        -UserPrincipalName 'admin@fiktivni.example' -Days 14 -IncludeSignInActivity -IncludeOneDrive -OutputPath $outDir *> $null

    $expected = 'licenses-skus.csv', 'licenses-sku-plans.csv', 'users-licenses.csv', 'users-service-plans.csv', 'licenses-summary.json',
    'mfa-registration.csv', 'mfa-admins-without-mfa.csv', 'mfa-security-defaults.json', 'mfa-conditional-access.csv', 'mfa-summary.json',
    'groups-m365.csv', 'groups-public.csv', 'groups-summary.json',
    'sharing-tenant.csv', 'sharing-sites.csv', 'sharing-summary.json',
    'links-audit-events.csv', 'links-audit-by-site.csv', 'links-audit-summary.json',
    'run-log.json', 'WS0-souhrn.md'
    foreach ($name in $expected) { Assert-True (Test-Path (Join-Path $outDir $name)) "výstup existuje: $name" }

    $runLog = Get-Content (Join-Path $outDir 'run-log.json') -Raw | ConvertFrom-Json
    Assert-True (@($runLog.Steps | Where-Object Status -ne 'OK').Count -eq 0) 'všechny kroky ve stavu OK'
    Assert-True ((Get-StubConnectCount) -eq 1) 'jedno přihlášení k Microsoft Graph pro všechny kroky'

    # --- Licenses ----------------------------------------------------------------------------------
    $userLicenses = Read-Csv $outDir 'users-licenses.csv'
    Assert-True ($userLicenses.Count -eq 4) 'users-licenses: 4 řádky (2 SKU + 1 SKU + host bez licence)'
    Assert-True (@($userLicenses | Where-Object { $_.UserPrincipalName -like 'eva@*' -and $_.FlagDisabledButLicensed -eq 'True' }).Count -eq 1) 'zakázaný účet s licencí označen'
    Assert-True (@($userLicenses | Where-Object { $_.AssignedVia -eq 'Group:g1' }).Count -eq 1) 'licence přes skupinu rozpoznána'
    Assert-True (@($userLicenses | Where-Object { $_.DisabledPlans -eq 'TEAMS1' }).Count -eq 1) 'vypnutý plán přeložen na název'
    $plans = Read-Csv $outDir 'users-service-plans.csv'
    Assert-True (@($plans | Where-Object { $_.ServicePlanName -eq 'TEAMS1' -and $_.PlanEnabled -eq 'False' }).Count -eq 1) 'plán TEAMS1 u uživatele vypnutý'

    # --- MFA ---------------------------------------------------------------------------------------
    $mfa = Get-Content (Join-Path $outDir 'mfa-summary.json') -Raw | ConvertFrom-Json
    Assert-True ($mfa.AdminsWithoutMfa -eq 1) 'správce bez MFA nalezen'
    Assert-True ($mfa.ConditionalAccessEnabledMfa -eq 0) 'report-only zásada se nepočítá jako vynucení'

    # --- Groups ------------------------------------------------------------------------------------
    $public = Read-Csv $outDir 'groups-public.csv'
    Assert-True ($public.Count -eq 2) 'veřejné skupiny: 2'
    Assert-True (@($public | Where-Object FlagNoOwner -eq 'True').Count -eq 1) 'veřejná skupina bez vlastníka označena'

    # --- Sharing settings --------------------------------------------------------------------------
    $sites = Read-Csv $outDir 'sharing-sites.csv'
    Assert-True ($sites.Count -eq 2) 'weby včetně OneDrive: 2'
    Assert-True (@($sites | Where-Object { $_.SharingCapability -eq 'ExternalUserAndGuestSharing' }).Count -eq 1) 'úroveň sdílení čtena per web (-Identity)'
    $tenant = Read-Csv $outDir 'sharing-tenant.csv'
    Assert-True (@($tenant | Where-Object { $_.Setting -eq 'RequireAnonymousLinksExpireInDays' -and $_.Risk -like 'Anonymní*' }).Count -eq 1) 'záporná expirace (-1) vyhodnocena bez chyby'

    # --- Audit log links ---------------------------------------------------------------------------
    $events = Read-Csv $outDir 'links-audit-events.csv'
    Assert-True ($events.Count -eq 2) 'události odkazů: 2 (dvě týdenní okna)'

    # --- Summary report ----------------------------------------------------------------------------
    $summary = Get-Content (Join-Path $outDir 'WS0-souhrn.md') -Raw -Encoding UTF8
    Assert-True ($summary -match 'Správci bez schopnosti MFA: 1') 'souhrn: kritický nález správce bez MFA'
    Assert-True ($summary -match 'MFA není vynuceno') 'souhrn: kritický nález nevynucené MFA'
    Assert-True ($summary -match 'odkazů „Kdokoli“') 'souhrn: nález odkazů Kdokoli'
    Assert-True ($summary -notmatch 'jan@fiktivni') 'souhrn neobsahuje UPN uživatelů'

    # --- Summary with missing inputs ---------------------------------------------------------------
    Write-Host 'New-WS0Summary (neúplné podklady)'
    $partial = Join-Path $outDir 'partial'
    New-Item -ItemType Directory -Path $partial | Out-Null
    Copy-Item (Join-Path $outDir 'mfa-summary.json') $partial
    & (Join-Path $auditDir 'New-WS0Summary.ps1') -ReportFolder $partial *> $null
    $partialMd = Get-Content (Join-Path $partial 'WS0-souhrn.md') -Raw -Encoding UTF8
    Assert-True ($partialMd -match 'Chybějící podklady') 'souhrn uvádí chybějící podklady'

    # --- Skip handling -----------------------------------------------------------------------------
    Write-Host 'Invoke-WS0Audit -Skip'
    $skipDir = Join-Path $outDir 'skip'
    & (Join-Path $auditDir 'Invoke-WS0Audit.ps1') -Skip SharingSettings, SharingLinks -OutputPath $skipDir *> $null
    $skipLog = Get-Content (Join-Path $skipDir 'run-log.json') -Raw | ConvertFrom-Json
    Assert-True (@($skipLog.Steps | Where-Object Status -eq 'Skipped').Count -eq 2) 'přeskočené kroky zapsány v run-log'
    Assert-True (-not (Test-Path (Join-Path $skipDir 'sharing-tenant.csv'))) 'přeskočený krok nic nevytvořil'

    # --- WS1: New-WS0AuditApp (changes tenant only with -Apply) -------------------------------------
    Write-Host 'New-WS0AuditApp'
    $appScript = Join-Path (Join-Path (Join-Path $repoRoot 'scripts') 'identity') 'New-WS0AuditApp.ps1'
    Import-Module Microsoft.Graph.Applications
    Reset-StubCreated
    & $appScript *> $null
    Assert-True (@(Get-StubCreated).Count -eq 0) 'výchozí režim (plán) nic nevytvoří'
    & $appScript -Apply -WhatIf *> $null
    Assert-True (@(Get-StubCreated).Count -eq 0) '-Apply -WhatIf nic nevytvoří'
    & $appScript -Apply -Confirm:$false *> $null
    $created = @(Get-StubCreated)
    Assert-True ($created.Count -eq 2) '-Apply vytvoří aplikaci a service principal'
    Assert-True ($created -contains 'app:Cleversystems WS0 Audit (read-only):5') 'aplikace má právě 5 delegovaných oprávnění'
    Reset-StubCreated
    Set-StubExistingApplication -Names 'Cleversystems WS0 Audit (read-only)'
    & $appScript -Apply -Confirm:$false *> $null
    Assert-True (@(Get-StubCreated).Count -eq 0) 'existující aplikace se nezakládá znovu'
    Set-StubExistingApplication -Names @()
}
finally {
    Remove-Item -LiteralPath $outDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Failures -eq 0) { Write-Host 'Všechny testy prošly.' -ForegroundColor Green }
else { Write-Host "Selhalo: $script:Failures" -ForegroundColor Red }
exit $script:Failures
