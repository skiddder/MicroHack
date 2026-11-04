<#
.SYNOPSIS
    Remove explicitly named, tagged Azure/on-prem RG pairs from one event subscription.
.DESCRIPTION
    Run as a coach before Console teardown. Requires an existing Az PowerShell
    context and Az.Accounts/Az.Resources. Supports -WhatIf and confirmation.
    No login, subscription switching, wildcard matching or managed-RG discovery.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][string[]]$AzureResourceGroupNames
)

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'common.ps1')
$context = Get-AzContext
if (-not $context -or $context.Subscription.Id -ne $SubscriptionId.ToString()) {
    throw 'Authenticate Az PowerShell to the explicit event SubscriptionId before cleanup. This script never logs in or switches subscriptions.'
}
if ($AzureResourceGroupNames.Count -eq 0 -or
    @($AzureResourceGroupNames | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -match '[*?\[\]]' }).Count -gt 0) {
    throw 'Supply exact Console Azure RG names, without empty names or wildcards.'
}

$groups = @(Get-AzResourceGroup -ErrorAction Stop)
$targets = @()
foreach ($azureName in @($AzureResourceGroupNames | Sort-Object -Unique)) {
    $onPremName = Get-ArcOnPremResourceGroupName -AzureResourceGroupName $azureName
    $azure = @($groups | Where-Object { $_.ResourceGroupName -eq $azureName })
    $onPrem = @($groups | Where-Object { $_.ResourceGroupName -eq $onPremName })
    if ($azure.Count -eq 0 -and $onPrem.Count -eq 0) {
        Write-Warning "Neither '$azureName' nor '$onPremName' exists. Nothing selected for this pair."
        continue
    }
    $source = if ($azure.Count -eq 1) { $azure[0] } else { $onPrem[0] }
    $userId = [guid]::Empty
    if (-not $source.Tags -or
        -not [guid]::TryParse([string]$source.Tags['microhackArcUserId'], [ref]$userId)) {
        throw "Cannot verify the participant tag for '$($source.ResourceGroupName)'. No groups have been deleted."
    }
    if ($azure.Count -eq 1 -and $azure[0].Tags['microhackArcPurpose'] -ne 'azure') {
        throw "Group '$azureName' is not tagged as an Azure exercise RG. No groups have been deleted."
    }
    if ($onPrem.Count -eq 1) {
        if (-not $onPrem[0].Tags -or $onPrem[0].Tags.Count -eq 0) {
            throw "On-prem resource group '$onPremName' has no ownership tags. No groups have been deleted."
        }
        $group = [pscustomobject]@{
            name = $onPremName
            tags = [pscustomobject]@{
                microhackArcPurpose = $onPrem[0].Tags['microhackArcPurpose']
                microhackArcUserId = $onPrem[0].Tags['microhackArcUserId']
                microhackArcAzureResourceGroup = $onPrem[0].Tags['microhackArcAzureResourceGroup']
            }
        }
        Assert-ArcOnPremResourceGroup -Group $group -AzureResourceGroupName $azureName -UserId $userId.ToString()
        $targets += $onPremName
    }
    if ($azure.Count -eq 1) { $targets += $azureName }
}

foreach ($name in $targets) {
    if ($PSCmdlet.ShouldProcess("/subscriptions/$SubscriptionId/resourceGroups/$name", 'Delete resource group and all its contents')) {
        if (-not (Remove-AzResourceGroup -Name $name -Force -ErrorAction Stop)) {
            throw "Deletion of resource group '$name' was not confirmed."
        }
    }
}
