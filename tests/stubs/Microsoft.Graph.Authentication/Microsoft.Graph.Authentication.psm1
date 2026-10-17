# Test stub with fictitious data only. Never contains real tenant data.
$script:Context = $null
$script:ConnectCount = 0
function Connect-MgGraph { param([string[]]$Scopes, $TenantId, $ContextScope, [switch]$NoWelcome)
    $script:ConnectCount++
    $script:Context = [pscustomobject]@{ Account = 'admin@fiktivni.example'; AuthType = 'Delegated'; Scopes = $Scopes }
}
function Disconnect-MgGraph { $script:Context = $null }
function Get-MgContext { $script:Context }
function Get-StubConnectCount { $script:ConnectCount }
