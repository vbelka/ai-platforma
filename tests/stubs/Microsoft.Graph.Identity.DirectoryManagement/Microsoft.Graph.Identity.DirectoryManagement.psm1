# Test stub with fictitious data only. Never contains real tenant data.
function Get-MgSubscribedSku { param([switch]$All)
    @(
        [pscustomobject]@{ SkuId = 'sku-1'; SkuPartNumber = 'FAKE_E3'; AppliesTo = 'User'; CapabilityStatus = 'Enabled'; ConsumedUnits = 3
            PrepaidUnits = [pscustomobject]@{ Enabled = 5; Warning = 0; Suspended = 0 }
            ServicePlans = @(
                [pscustomobject]@{ ServicePlanId = 'p1'; ServicePlanName = 'TEAMS1'; ProvisioningStatus = 'Success'; AppliesTo = 'User' },
                [pscustomobject]@{ ServicePlanId = 'p2'; ServicePlanName = 'SHAREPOINTENTERPRISE'; ProvisioningStatus = 'Success'; AppliesTo = 'User' }) },
        [pscustomobject]@{ SkuId = 'sku-2'; SkuPartNumber = 'FAKE_COPILOT'; AppliesTo = 'User'; CapabilityStatus = 'Enabled'; ConsumedUnits = 1
            PrepaidUnits = [pscustomobject]@{ Enabled = 1; Warning = 0; Suspended = 0 }
            ServicePlans = @([pscustomobject]@{ ServicePlanId = 'p3'; ServicePlanName = 'FAKE_COPILOT_PLAN'; ProvisioningStatus = 'Success'; AppliesTo = 'User' }) }
    )
}
