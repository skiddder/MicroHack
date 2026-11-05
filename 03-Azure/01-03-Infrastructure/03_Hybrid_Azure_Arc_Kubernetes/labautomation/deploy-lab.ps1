param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('subscription', 'resourcegroup', 'resourcegroup-with-subscriptionowner')]
    [string]$DeploymentType,
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    [string]$ResourceGroupName = '',
    [string[]]$PreferredLocation = @(),
    [string[]]$AllowedEntraUserIds = @()
)

. (Join-Path $PSScriptRoot 'common.ps1')
Assert-K8sContext $SubscriptionId
if ($DeploymentType -eq 'subscription' -or [string]::IsNullOrWhiteSpace($ResourceGroupName)) {
    throw 'This lab requires a resource group supplied by Hackbox Console.'
}
if ($ResourceGroupName -eq $script:SharedGroupName) {
    throw 'A participant deployment must not target the shared Bastion resource group.'
}
if ($AllowedEntraUserIds.Count -ne 1) {
    throw 'Exactly one participant per lab invocation is required.'
}
$regions = @(Get-K8sRegions $PreferredLocation)
$userId = ([guid]$AllowedEntraUserIds[0]).ToString()
$shared = Get-AzResourceGroup -Name $script:SharedGroupName -ErrorAction Stop
$index = 0
if (-not $shared.Tags -or $shared.Tags['microhack'] -ne 'arc-kubernetes' -or
    -not [int]::TryParse($shared.Tags["k8s-user-$userId"], [ref]$index) -or $index -lt 1 -or $index -gt 199) {
    throw 'No valid participant network assignment exists. Run shared-deploy-lab.ps1 first.'
}
$prefix = 'k8s' + (Get-MhhStableHash -Value $userId -Length 12)
$onpremGroupName = "$prefix-onprem"
$onpremGroup = Get-AzResourceGroup -Name $onpremGroupName -ErrorAction SilentlyContinue
if ($onpremGroup -and (-not $onpremGroup.Tags -or $onpremGroup.Tags['microhackUserId'] -ne $userId -or
    $onpremGroup.Tags['microhackExerciseGroup'] -ne $ResourceGroupName)) {
    throw "Resource group '$onpremGroupName' already exists but is not assigned to this participant and exercise group."
}
$exercise = Invoke-MhhDeploymentWithRegionFallback -PreferredLocations $regions `
    -ResourceGroupName $ResourceGroupName -RgOwnerEntraObjectIds $AllowedEntraUserIds `
    -TemplateFile (Join-Path $PSScriptRoot 'exercise.bicep') `
    -TemplateParameterObject @{
        labPrefix = $prefix
        acrName = 'mh' + (Get-MhhStableHash -Value @($SubscriptionId, $ResourceGroupName) -Length 18)
    } -Tag @{
        SecurityControl = 'Ignore'
        microhack = 'arc-kubernetes'
        microhackUserId = $userId
        microhackOnpremGroup = $onpremGroupName
    }
if (-not $exercise.Success) {
    throw 'The exercise resource deployment did not succeed.'
}
$password = New-MhhStablePassword -Purpose 'vm-admin'
$tokenText = New-MhhStablePassword -Purpose 'k3s-token'
$tokenBytes = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($tokenText))
$token = [Convert]::ToHexString($tokenBytes).ToLowerInvariant()
$masterIp = "10.$index.1.10"
$hubId = "/subscriptions/$SubscriptionId/resourceGroups/$script:SharedGroupName/providers/Microsoft.Network/virtualNetworks/mh-k8s-hub"
$configuration = @{
    admin_user = 'mhadmin'
    admin_password = $password
    workstation_ip = "10.$index.2.10"
    master_ip = $masterIp
    lab_prefix = $prefix
    resource_group = $ResourceGroupName
    onprem_resource_group = $onpremGroupName
    location = $exercise.LocationUsed
    acr_name = $exercise.Outputs.acrName
    workspace_name = $exercise.Outputs.workspaceName
}
$winrm = Get-K8sAsset 'scripts\enable-winrm.ps1'
$winrmEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($winrm))
$result = Invoke-MhhDeploymentWithRegionFallback -PreferredLocations $regions `
    -ResourceGroupName $onpremGroupName -RgOwnerEntraObjectIds $AllowedEntraUserIds `
    -TemplateFile (Join-Path $PSScriptRoot 'main.bicep') `
    -TemplateParameterObject @{
        labPrefix = $prefix
        networkIndex = $index
        hubVnetId = $hubId
        adminPassword = $password
        masterSetupScript = Get-K8sBootstrap -Role master -ClusterToken $token -MasterIp $masterIp
        workerSetupScript = Get-K8sBootstrap -Role worker -ClusterToken $token -MasterIp $masterIp
        winrmCommand = "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $winrmEncoded"
    } -Tag @{
        SecurityControl = 'Ignore'
        microhack = 'arc-kubernetes'
        microhackUserId = $userId
        microhackExerciseGroup = $ResourceGroupName
    }
if (-not $result.Success) {
    throw 'The participant deployment did not succeed.'
}

Update-MhhToken | Out-Null
$workstation = New-AzResourceGroupDeployment -ResourceGroupName $onpremGroupName `
    -Name "workstation-$prefix" -TemplateFile (Join-Path $PSScriptRoot 'workstation-setup.bicep') `
    -TemplateParameterObject @{
        masterVmName = "$prefix-k8s-master"
        setupScript = Get-K8sWorkstationScript
        configuration = $configuration
    } -ErrorAction Stop
if ($workstation.ProvisioningState -ne 'Succeeded') {
    throw 'Workstation provisioning and readiness verification did not succeed.'
}

$lockName = 'k8s-hub-' + (Get-MhhStableHash -Value $SubscriptionId -Length 24)
Invoke-MhhSynchronized -Name $lockName -ScriptBlock {
    Update-MhhToken | Out-Null
    $peerings = @(Invoke-K8sAz @(
        'network', 'vnet', 'peering', 'list',
        '--resource-group', $script:SharedGroupName, '--vnet-name', 'mh-k8s-hub'
    ))
    $oldPeering = @($peerings | Where-Object { $_.name -eq "to-$prefix" })
    if ($oldPeering.Count -gt 0 -and $oldPeering[0].peeringState -eq 'Disconnected') {
        Invoke-K8sAz @(
            'network', 'vnet', 'peering', 'delete', '--resource-group', $script:SharedGroupName,
            '--vnet-name', 'mh-k8s-hub', '--name', "to-$prefix"
        ) | Out-Null
    }
    $peering = New-AzResourceGroupDeployment -ResourceGroupName $script:SharedGroupName `
        -Name "peering-$prefix" -TemplateFile (Join-Path $PSScriptRoot 'hub-peering.bicep') `
        -TemplateParameterObject @{ spokeVnetId = $result.Outputs.spokeVnetId; labPrefix = $prefix } -ErrorAction Stop
    if ($peering.ProvisioningState -ne 'Succeeded') {
        throw "Hub peering for '$prefix' failed."
    }
    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    do {
        $state = Invoke-K8sAz @(
            'network', 'vnet', 'peering', 'show', '--resource-group', $script:SharedGroupName,
            '--vnet-name', 'mh-k8s-hub', '--name', "to-$prefix"
        )
        if ($state.peeringState -eq 'Connected') { break }
        if ([DateTime]::UtcNow -ge $deadline) {
            throw "Hub peering for '$prefix' did not reach Connected."
        }
        Start-Sleep -Seconds 10
    } while ($true)
} | Out-Null

@{ HackboxCredential = @{ name = 'VM Admin Username'; value = 'mhadmin'; note = 'Windows workstation and K3s nodes' } }
@{ HackboxCredential = @{ name = 'VM Admin Password'; value = $password; note = 'Windows workstation and K3s nodes' } }
@{ HackboxCredential = @{ name = 'Workstation VM'; value = "$prefix-workstation"; note = $onpremGroupName } }
@{ HackboxCredential = @{ name = 'Workstation Resource ID'; value = $result.Outputs.workstationId; note = 'Connect using the shared Bastion' } }
@{ HackboxCredential = @{ name = 'K3s Master IP'; value = $masterIp; note = 'Private address; reachable from WSL on the workstation' } }
@{ HackboxCredential = @{ name = 'On-prem Resource Group'; value = $onpremGroupName; note = 'Four VMs, participant network and outbound NAT' } }
@{ HackboxCredential = @{ name = 'Arc Resource Group'; value = $ResourceGroupName; note = 'Exercise resources, ACR and Log Analytics' } }
@{ HackboxCredential = @{ name = 'Container Registry'; value = $exercise.Outputs.acrName; note = 'Use this name instead of the legacy <xy>mhacr example' } }
@{ HackboxCredential = @{ name = 'Log Analytics Workspace'; value = $exercise.Outputs.workspaceName; note = $ResourceGroupName } }
