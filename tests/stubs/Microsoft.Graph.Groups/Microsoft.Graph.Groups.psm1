# Test stub with fictitious data only. Never contains real tenant data.
function Get-MgGroup { param([switch]$All, $Filter, $Property)
    @(
        [pscustomobject]@{ Id = 'g1'; DisplayName = 'Obchod'; Mail = 'obchod@fiktivni.example'; Visibility = 'Public'; ResourceProvisioningOptions = @('Team') },
        [pscustomobject]@{ Id = 'g2'; DisplayName = 'Vedení'; Visibility = 'Private'; ResourceProvisioningOptions = @('Team') },
        [pscustomobject]@{ Id = 'g3'; DisplayName = 'Projekt X'; Visibility = 'Public'; ResourceProvisioningOptions = @() }
    )
}
function Get-MgGroupOwner { param($GroupId, [switch]$All) if ($GroupId -eq 'g3') { @() } else { @([pscustomobject]@{ Id = 'u1' }) } }
