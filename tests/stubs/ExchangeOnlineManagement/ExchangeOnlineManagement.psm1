# Test stub with fictitious data only. Never contains real tenant data.
$script:Sessions = @{}
function Connect-ExchangeOnline { param([switch]$ShowBanner, $UserPrincipalName) }
function Disconnect-ExchangeOnline { param([switch]$Confirm) }
function Get-AdminAuditLogConfig { [pscustomobject]@{ UnifiedAuditLogIngestionEnabled = $true } }
function Search-UnifiedAuditLog { param($StartDate, $EndDate, $Operations, $SessionId, $SessionCommand, $ResultSize)
    # Second call within a session returns nothing (end of paging).
    if ($script:Sessions[$SessionId]) { return @() }
    $script:Sessions[$SessionId] = $true
    if ($Operations -ne 'AnonymousLinkCreated') { return @() }
    $data = @{ CreationTime = $StartDate.ToString('s'); SiteUrl = 'https://fiktivni.sharepoint.com/sites/obchod/'
        ObjectId = 'https://fiktivni.sharepoint.com/sites/obchod/Shared Documents/nabidka.docx'; SourceFileName = 'nabidka.docx'
        ItemType = 'File'; ClientIP = '192.0.2.10' } | ConvertTo-Json
    @([pscustomobject]@{ Identity = [guid]::NewGuid().ToString(); Operations = $Operations; UserIds = 'jan@fiktivni.example'; AuditData = $data })
}
