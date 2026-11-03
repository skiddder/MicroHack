param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$PreferredLocation,

    [Parameter(Mandatory = $false)]
    [string[]]$AllowedEntraUserIds = @()
)

. (Join-Path $PSScriptRoot 'common.ps1')
Assert-ArcAssets
Assert-ArcContext
$regions = @(Get-ArcRegions -Locations $PreferredLocation)
$placement = @(New-ArcPlacement -UserIds $AllowedEntraUserIds -Regions $regions)
$previous = @(Get-ArcPlacement)
$requiresReplan = $false
if ($previous.Count -gt 0) {
    foreach ($entry in $previous) {
        $next = @($placement | Where-Object { $_.userId -eq $entry.userId })
        if ($next.Count -ne 1 -or $next[0].location -ne $entry.location) {
            $requiresReplan = $true
        }
    }
}
if ($requiresReplan) {
    $inventory = Invoke-ArcAz -Arguments @('resource', 'list', '--query', '{resources:@}')
    if (-not $inventory -or -not $inventory.PSObject.Properties['resources'] -or $inventory.resources -isnot [array]) {
        throw 'Cannot verify that the subscription is empty: Azure returned an invalid resource inventory. Previous placement was not changed.'
    }
    $approvedWorkspaceId = '/subscriptions/06dd34f3-80d4-42a0-ac31-446add752cd8/resourceGroups/McapsGovernance/providers/Microsoft.OperationalInsights/workspaces/mcaps42a0ac31446add752cd8-la'
    $blocking = @($inventory.resources | Where-Object {
        $_.type -notin @('Microsoft.Resources/resourceGroups', 'Microsoft.Resources/deployments') -and
        -not ($_.type -eq 'Microsoft.OperationalInsights/workspaces' -and $_.id -eq $approvedWorkspaceId)
    })
    if ($blocking.Count -gt 0) {
        $examples = ($blocking | Select-Object -First 3 | ForEach-Object { $_.id }) -join ', '
        throw "The participant or region list would remove or relocate a previously assigned user, but the subscription contains $($blocking.Count) resource(s). Restore the original lists or have the coach inspect and clean up first. Previous placement was not changed. Examples: $examples"
    }
    Write-Warning "No blocking resources remain after excluding resource groups, deployment metadata and the explicitly approved workspace '$approvedWorkspaceId'. Replacing stale participant placement for the Console-selected users and regions; no Azure resources will be deleted or moved."
}
$deploymentLocation = $regions[0]
if ($previous.Count -gt 0) {
    $storedLocation = Invoke-ArcAz -Arguments @(
        'deployment', 'sub', 'show', '--name', $script:ArcPlacementDeployment, '--query', 'location'
    )
    if ($storedLocation -isnot [string] -or [string]::IsNullOrWhiteSpace($storedLocation)) {
        throw 'Cannot read the existing placement deployment location. Previous placement was not changed.'
    }
    $deploymentLocation = $storedLocation
}

$providers = @(
    'Microsoft.Compute', 'Microsoft.Network', 'Microsoft.HybridCompute',
    'Microsoft.GuestConfiguration', 'Microsoft.HybridConnectivity', 'Microsoft.AzureArcData',
    'Microsoft.OperationsManagement', 'Microsoft.OperationalInsights', 'Microsoft.Insights',
    'Microsoft.KeyVault', 'Microsoft.Security', 'Microsoft.PolicyInsights',
    'Microsoft.Storage', 'Microsoft.Automation', 'Microsoft.Maintenance'
)
foreach ($provider in $providers) {
    $state = Invoke-ArcAz -Arguments @('provider', 'show', '--namespace', $provider)
    if ($state.registrationState -ne 'Registered') {
        Write-Host "Registering $provider."
        Invoke-ArcAz -Arguments @('provider', 'register', '--namespace', $provider, '--wait') | Out-Null
        $state = Invoke-ArcAz -Arguments @('provider', 'show', '--namespace', $provider)
        if ($state.registrationState -ne 'Registered') {
            throw "Resource provider $provider is not registered."
        }
    }
}

Test-ArcCapacity -Placement $placement

$template = @{
    '$schema' = 'https://schema.management.azure.com/schemas/2018-05-01/subscriptionDeploymentTemplate.json#'
    contentVersion = '1.0.0.0'
    resources = @()
    outputs = @{ placement = @{ type = 'array'; value = $placement } }
}
$templatePath = Join-Path ([System.IO.Path]::GetTempPath()) "microhack-arc-placement-$([guid]::NewGuid().ToString('N')).json"
try {
    $template | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $templatePath -Encoding utf8
    Update-MhhToken | Out-Null
    $result = New-AzSubscriptionDeployment -Name $script:ArcPlacementDeployment `
        -Location $deploymentLocation -TemplateFile $templatePath -ErrorAction Stop
    if ($result.ProvisioningState -ne 'Succeeded') {
        throw "Saving participant placement failed: $($result.ProvisioningState)."
    }
} finally {
    if (Test-Path -LiteralPath $templatePath) {
        Remove-Item -LiteralPath $templatePath -Force -ErrorAction Stop
    }
}
Write-Host "Prepared $($placement.Count) labs in subscription $SubscriptionId. No shared resource group was created."
