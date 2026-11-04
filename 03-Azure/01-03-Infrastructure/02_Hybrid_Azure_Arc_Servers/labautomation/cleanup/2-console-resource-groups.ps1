<#
.SYNOPSIS
    Clean up verified participant RGs and check Azure Monitor managed-RG cleanup.
.DESCRIPTION
    Run as a coach before Console teardown. Requires an existing Az PowerShell
    context and Az.Accounts/Az.Resources. Supports -WhatIf and confirmation.
    Includes explicitly linked, tagged exercise RGs. Unknown resources are reported,
    not deleted. Azure Monitor managed RGs are removed by their owning service.
    No login, subscription switching or wildcard matching.
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
    if ($azureName -eq 'McapsGovernance') { throw 'The governance RG cannot be a cleanup target.' }
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
    foreach ($extra in $groups) {
        if ($extra.ResourceGroupName -in @($azureName, $onPremName) -or -not $extra.Tags -or
            $extra.Tags['microhackArcPurpose'] -ne 'exercise' -or
            $extra.Tags['microhackArcAzureResourceGroup'] -ne $azureName) { continue }
        if ($extra.ResourceGroupName -eq 'McapsGovernance' -or
            $extra.Tags['microhackArcUserId'] -ne $userId.ToString() -or
            ($extra.PSObject.Properties['ManagedBy'] -and $extra.ManagedBy)) {
            throw "Cannot verify additional exercise RG '$($extra.ResourceGroupName)'. No groups have been deleted."
        }
        $targets += $extra.ResourceGroupName
    }
    if ($azure.Count -eq 1) { $targets += $azureName }
}

$managedGroups = @{}
foreach ($name in $targets) {
    $workspaces = @(Get-AzResource -ResourceGroupName $name -ResourceType 'Microsoft.Monitor/accounts' -ExpandProperties -ErrorAction Stop)
    foreach ($workspace in $workspaces) {
        $properties = $workspace.Properties | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        if (-not $properties -or -not $properties.PSObject.Properties['defaultIngestionSettings'] -or
            -not $properties.defaultIngestionSettings) {
            throw "Cannot verify managed resources for workspace '$($workspace.ResourceId)'. No groups have been deleted."
        }
        $settings = $properties.defaultIngestionSettings
        $linkedGroups = @()
        $fields = @{
            dataCollectionRuleResourceId = 'dataCollectionRules'
            dataCollectionEndpointResourceId = 'dataCollectionEndpoints'
        }
        foreach ($field in $fields.Keys) {
            $pattern = "^/subscriptions/$SubscriptionId/resourceGroups/([^/]+)/providers/Microsoft\.Insights/$($fields[$field])/[^/]+$"
            if (-not $settings.PSObject.Properties[$field] -or [string]$settings.$field -notmatch $pattern) {
                throw "Invalid managed-resource reference '$field' for workspace '$($workspace.ResourceId)'. No groups have been deleted."
            }
            $linkedGroups += $Matches[1]
        }
        $linkedGroups = @($linkedGroups | Sort-Object -Unique)
        if ($linkedGroups.Count -ne 1 -or $linkedGroups[0] -in $targets -or $linkedGroups[0] -eq 'McapsGovernance') {
            throw "Ambiguous or protected managed RG for workspace '$($workspace.ResourceId)'. No groups have been deleted."
        }
        $managedName = $linkedGroups[0]
        $managed = @($groups | Where-Object { $_.ResourceGroupName -eq $managedName })
        if ($managed.Count -eq 1 -and (
            ($managed[0].PSObject.Properties['ManagedBy'] -and $managed[0].ManagedBy -and
                $managed[0].ManagedBy -ne $workspace.ResourceId) -or
            ($managed[0].Tags -and $managed[0].Tags['microhackArcPurpose'] -in @('azure', 'onprem', 'exercise')))) {
            throw "Managed RG '$managedName' has a conflicting owner or purpose. No groups have been deleted."
        }
        if ($managedGroups.ContainsKey($managedName) -and $managedGroups[$managedName].WorkspaceId -ne $workspace.ResourceId) {
            throw "Managed RG '$managedName' is referenced by multiple workspaces. No groups have been deleted."
        }
        $managedGroups[$managedName] = @{ WorkspaceId = $workspace.ResourceId; ParentGroup = $name }
        Write-Host "Indirect service cleanup: '$($workspace.ResourceId)' owns managed RG '$managedName'. It will not be deleted directly."
    }
}

$deleted = @()
foreach ($name in $targets) {
    if ($PSCmdlet.ShouldProcess("/subscriptions/$SubscriptionId/resourceGroups/$name", 'Delete resource group and all its contents')) {
        if (-not (Remove-AzResourceGroup -Name $name -Force -ErrorAction Stop)) {
            throw "Deletion of resource group '$name' was not confirmed."
        }
        $deleted += $name
    }
}

$toVerify = @($managedGroups.Keys | Where-Object { $managedGroups[$_].ParentGroup -in $deleted })
$remainingManaged = @()
if ($toVerify.Count -gt 0) {
    # Workspace deletion triggers asynchronous service cleanup of its managed RG.
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        $remainingManaged = @(Get-AzResourceGroup -ErrorAction Stop | Where-Object { $_.ResourceGroupName -in $toVerify })
        if ($remainingManaged.Count -eq 0) { break }
        if ($attempt -lt 59) { Start-Sleep -Seconds 5 }
    }
}

$outside = @(Get-AzResourceGroup -ErrorAction Stop | Where-Object {
    $_.ResourceGroupName -notin $targets -and -not $managedGroups.ContainsKey($_.ResourceGroupName)
})
$outsideResources = @(Get-AzResource -ErrorAction Stop | Where-Object {
    $_.ResourceGroupName -notin $targets -and -not $managedGroups.ContainsKey([string]$_.ResourceGroupName)
})
if ($outside.Count -gt 0 -or $outsideResources.Count -gt 0) {
    Write-Warning 'RGs/resources outside the verified cleanup scope remain untouched. This does not classify them as participant-created.'
    foreach ($group in $outside) {
        [pscustomobject]@{
            Status = 'NotAssigned'
            ResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$($group.ResourceGroupName)"
        }
    }
    foreach ($resource in $outsideResources) {
        [pscustomobject]@{ Status = 'NotAssigned'; ResourceId = $resource.ResourceId }
    }
}
if ($remainingManaged.Count -gt 0) {
    throw "Azure Monitor managed-RG deletion was not verified after waiting: $($remainingManaged.ResourceGroupName -join ', '). Inspect the service cleanup; no direct deletion was attempted."
}
foreach ($name in $toVerify) {
    Write-Host "Verified service cleanup: managed RG '$name' no longer exists."
}
