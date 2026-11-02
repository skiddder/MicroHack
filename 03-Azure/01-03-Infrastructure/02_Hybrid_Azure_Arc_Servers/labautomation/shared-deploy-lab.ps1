param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$PreferredLocation,

    [Parameter(Mandatory = $false)]
    [string[]]$AllowedEntraUserIds = @()
)

. (Join-Path $PSScriptRoot 'common.ps1')
Assert-ArcContext
$regions = @(Get-ArcRegions -Locations $PreferredLocation)
$placement = @(New-ArcPlacement -UserIds $AllowedEntraUserIds -Regions $regions)
$previous = @(Get-ArcPlacement)
if ($previous.Count -gt 0) {
    foreach ($entry in $previous) {
        $next = @($placement | Where-Object { $_.userId -eq $entry.userId })
        if ($next.Count -ne 1 -or $next[0].location -ne $entry.location) {
            throw 'The participant list would remove or relocate a previously assigned user. Restore the original list or have the coach clean up the previous event first.'
        }
    }
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
Update-MhhToken | Out-Null
$result = New-AzSubscriptionDeployment -Name $script:ArcPlacementDeployment `
    -Location $regions[0] -TemplateObject $template -ErrorAction Stop
if ($result.ProvisioningState -ne 'Succeeded') {
    throw "Saving participant placement failed: $($result.ProvisioningState)."
}
Write-Host "Prepared $($placement.Count) labs in subscription $SubscriptionId. No shared resource group was created."
