<#
.SYNOPSIS
    Shared helpers for WS0 audit scripts (read-only).

.DESCRIPTION
    Dopad na tenant: ŽÁDNÝ. Modul neobsahuje žádné volání Microsoft 365 / Entra ID.
    Pouze vytváří lokální složku pro výstupy a zapisuje CSV/JSON soubory.

    Výstupy se ukládají do <repo>/reports/<yyyy-MM-dd>_WS0, pokud není zadán -OutputPath.
    Složka /reports je v .gitignore – výstupy obsahují osobní údaje (UPN, jména) a nesmí do Gitu.
#>

Set-StrictMode -Version Latest

function Get-AuditOutputFolder {
    [CmdletBinding()]
    param(
        [string]$OutputPath
    )

    if (-not $OutputPath) {
        $repoRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName
        $OutputPath = Join-Path (Join-Path $repoRoot 'reports') ('{0}_WS0' -f (Get-Date -Format 'yyyy-MM-dd'))
    }

    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    (Resolve-Path $OutputPath).Path
}

function Export-AuditCsv {
    # UTF-8 with BOM so that Excel (cs-CZ) opens diacritics correctly; semicolon delimiter for cs-CZ Excel.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$InputObject,
        [Parameter(Mandatory)] [string]$Folder,
        [Parameter(Mandatory)] [string]$FileName
    )

    $path = Join-Path $Folder $FileName
    $encoding = if ($PSVersionTable.PSEdition -eq 'Core') { 'utf8BOM' } else { 'UTF8' }

    if ($InputObject.Count -eq 0) {
        # Write an empty marker so that the reviewer sees the check ran and found nothing.
        Set-Content -Path $path -Value '# Bez nálezů' -Encoding $encoding
    }
    else {
        $InputObject | Export-Csv -Path $path -NoTypeInformation -Delimiter ';' -Encoding $encoding
    }

    Write-Host ("  -> {0} ({1} řádků)" -f $path, $InputObject.Count)
}

function Export-AuditJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$InputObject,
        [Parameter(Mandatory)] [string]$Folder,
        [Parameter(Mandatory)] [string]$FileName
    )

    $path = Join-Path $Folder $FileName
    $encoding = if ($PSVersionTable.PSEdition -eq 'Core') { 'utf8BOM' } else { 'UTF8' }
    $InputObject | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding $encoding
    Write-Host ("  -> {0}" -f $path)
}

function Assert-AuditModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]]$Name
    )

    foreach ($module in $Name) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            throw ("Chybí PowerShell modul '{0}'. Nainstalujte: Install-Module {0} -Scope CurrentUser" -f $module)
        }
    }
}

function Join-AuditValue {
    # Flattens a collection into one CSV cell.
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    (@($Value) | Where-Object { $_ -ne $null -and "$_" -ne '' }) -join ', '
}

Export-ModuleMember -Function Get-AuditOutputFolder, Export-AuditCsv, Export-AuditJson, Assert-AuditModule, Join-AuditValue
