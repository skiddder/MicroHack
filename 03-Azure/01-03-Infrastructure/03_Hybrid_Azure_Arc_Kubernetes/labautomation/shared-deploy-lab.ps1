param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    [Parameter(Mandatory = $true)]
    [string[]]$PreferredLocation,
    [string[]]$AllowedEntraUserIds = @()
)

. (Join-Path $PSScriptRoot 'common.ps1')
Assert-K8sContext $SubscriptionId
$regions = @(Get-K8sRegions $PreferredLocation)
$userIds = @($AllowedEntraUserIds | ForEach-Object { ([guid]$_).ToString() } | Sort-Object -Unique)
if ($userIds.Count -eq 0 -or $userIds.Count -gt 32) {
    throw 'The shared deployment requires between 1 and 32 participants per subscription (network assignment tags).'
}

foreach ($provider in @(
    'Microsoft.Compute', 'Microsoft.Network', 'Microsoft.ContainerRegistry',
    'Microsoft.OperationalInsights', 'Microsoft.DevTestLab', 'Microsoft.Kubernetes',
    'Microsoft.KubernetesConfiguration', 'Microsoft.ExtendedLocation', 'Microsoft.AzureArcData',
    'Microsoft.ContainerService', 'Microsoft.Security', 'Microsoft.PolicyInsights', 'Microsoft.Insights'
)) {
    Update-MhhToken | Out-Null
    Register-AzResourceProvider -ProviderNamespace $provider -ErrorAction Stop | Out-Null
    $deadline = [DateTime]::UtcNow.AddMinutes(10)
    while ((Get-AzResourceProvider -ProviderNamespace $provider -ErrorAction Stop).RegistrationState -ne 'Registered') {
        if ([DateTime]::UtcNow -ge $deadline) {
            throw "Timed out registering resource provider '$provider'."
        }
        Start-Sleep -Seconds 10
        Update-MhhToken | Out-Null
    }
}

$group = Get-AzResourceGroup -Name $script:SharedGroupName -ErrorAction SilentlyContinue
if ($group -and (-not $group.Tags -or $group.Tags['microhack'] -ne 'arc-kubernetes')) {
    throw "Resource group '$script:SharedGroupName' exists but does not belong to this MicroHack."
}
$tags = @{ SecurityControl = 'Ignore'; microhack = 'arc-kubernetes' }
$usedIndices = @()
if ($group -and $group.Tags) {
    foreach ($key in $group.Tags.Keys) {
        if ($key -notin @('SecurityControl', 'microhack')) {
            $tags[$key] = $group.Tags[$key]
        }
        if ($key -like 'k8s-user-*') {
            $index = 0
            if (-not [int]::TryParse($group.Tags[$key], [ref]$index) -or $index -lt 1 -or $index -gt 199 -or $index -in $usedIndices) {
                throw "Invalid or duplicate network assignment in shared resource group tag '$key'."
            }
            $tags[$key] = [string]$index
            $usedIndices += $index
        }
    }
}
foreach ($userId in $userIds) {
    $key = "k8s-user-$userId"
    if (-not $tags.ContainsKey($key)) {
        $index = @(1..199 | Where-Object { $_ -notin $usedIndices } | Select-Object -First 1)
        if ($index.Count -ne 1) {
            throw 'No non-overlapping participant network remains in this subscription.'
        }
        $tags[$key] = [string]$index[0]
        $usedIndices += $index[0]
    }
}
if ($tags.Count -gt 45) {
    throw 'Shared resource group tags leave insufficient space for the platform deployment tags (Azure limit: 50).'
}

$result = Invoke-MhhDeploymentWithRegionFallback -PreferredLocations $regions `
    -ResourceGroupName $script:SharedGroupName `
    -TemplateFile (Join-Path $PSScriptRoot 'shared.bicep') `
    -TemplateParameterObject @{ participantIds = $userIds } -Tag $tags
if (-not $result.Success) {
    throw 'The shared Bastion deployment did not succeed.'
}

@{ HackboxCredential = @{ name = 'Bastion Name'; value = $result.Outputs.bastionName; note = $script:SharedGroupName } }
@{ HackboxCredential = @{ name = 'Bastion Resource Group'; value = $script:SharedGroupName; note = 'Shared Bastion for this subscription' } }
