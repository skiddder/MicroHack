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
$onpremGroupName = "$ResourceGroupName-onprem"
if ($onpremGroupName.Length -gt 90) {
    throw "Exercise resource group '$ResourceGroupName' is too long to append '-onprem' (Azure limit: 90 characters)."
}
$workstationName = $ResourceGroupName -replace '^rg-', ''
if ($workstationName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
    throw "Cannot derive a valid workstation VM name from exercise resource group '$ResourceGroupName' (maximum 64 characters)."
}
$workspaceName = "$workstationName-law"
if ($workspaceName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{2,61}[A-Za-z0-9]$') {
    throw "Cannot derive a valid Log Analytics workspace name '$workspaceName' (4-63 characters, letters, digits and hyphens only)."
}
$acrStem = $workstationName.ToLowerInvariant() -replace '[^a-z0-9]', ''
if ($acrStem.Length -gt 39) {
    Write-Warning 'The ACR participant name is shortened to 39 characters to fit the Azure name limit.'
    $acrStem = $acrStem.Substring(0, 39)
}
$acrSuffix = (Get-MhhStableHash -Value @($SubscriptionId, $ResourceGroupName) -Length 12).Substring(0, 8)
$acrName = 'acr' + $acrStem + $acrSuffix
$groups = @(Get-AzResourceGroup -ErrorAction Stop)
$conflicts = @($groups | Where-Object {
    $_.ResourceGroupName -ne $onpremGroupName -and (
        $_.ResourceGroupName -eq "$prefix-onprem" -or
        ($_.Tags -and $_.Tags['microhackExerciseGroup'] -eq $ResourceGroupName)
    )
})
if ($conflicts.Count -gt 0) {
    throw "Cleanup required before deployment: existing on-prem resource group(s) '$($conflicts.ResourceGroupName -join ', ')' conflict with '$onpremGroupName'. No resource groups were deleted or created. Clean up the old lab before retrying."
}
$onpremGroup = $groups | Where-Object { $_.ResourceGroupName -eq $onpremGroupName }
if ($onpremGroup -and (-not $onpremGroup.Tags -or $onpremGroup.Tags['microhackUserId'] -ne $userId -or
    $onpremGroup.Tags['microhackExerciseGroup'] -ne $ResourceGroupName)) {
    throw "Resource group '$onpremGroupName' already exists but is not assigned to this participant and exercise group."
}
if ($onpremGroup) {
    $oldWorkstations = @(Invoke-K8sAz @('vm', 'list', '--resource-group', $onpremGroupName) | Where-Object {
        $_.name -ne $workstationName -and (
            $_.name -eq "$prefix-workstation" -or ($_.tags -and $_.tags.Role -eq 'workstation')
        )
    })
    if ($oldWorkstations.Count -gt 0) {
        throw "Cleanup required before deployment: workstation VM(s) '$($oldWorkstations.name -join ', ')' conflict with '$workstationName'. Azure VMs cannot be renamed; no replacement VM was created."
    }
}
if ($groups | Where-Object { $_.ResourceGroupName -eq $ResourceGroupName }) {
    $legacyAcrName = 'mh' + (Get-MhhStableHash -Value @($SubscriptionId, $ResourceGroupName) -Length 18)
    $oldExerciseResources = @(Invoke-K8sAz @('resource', 'list', '--resource-group', $ResourceGroupName) | Where-Object {
        ($_.type -eq 'Microsoft.ContainerRegistry/registries' -and $_.name -eq $legacyAcrName) -or
        ($_.type -eq 'Microsoft.OperationalInsights/workspaces' -and $_.name -eq "$prefix-law")
    })
    if ($oldExerciseResources.Count -gt 0) {
        throw "Cleanup required before deployment: legacy exercise resource(s) '$($oldExerciseResources.name -join ', ')' conflict with the participant naming scheme. No replacement registry or workspace was created."
    }
}
$hubId = "/subscriptions/$SubscriptionId/resourceGroups/$script:SharedGroupName/providers/Microsoft.Network/virtualNetworks/mh-k8s-hub"
$spokeId = "/subscriptions/$SubscriptionId/resourceGroups/$onpremGroupName/providers/Microsoft.Network/virtualNetworks/$prefix-k8s-vnet"
$lockName = 'k8s-hub-' + (Get-MhhStableHash -Value $SubscriptionId -Length 24)
Invoke-MhhSynchronized -Name $lockName -ScriptBlock {
    Write-Host "[peering] Checking hub peering for '$prefix' before infrastructure deployment."
    Repair-K8sHubPeering -SubscriptionId $SubscriptionId -LabPrefix $prefix -SpokeVnetId $spokeId
} | Out-Null
$exercise = Invoke-MhhDeploymentWithRegionFallback -PreferredLocations $regions `
    -ResourceGroupName $ResourceGroupName -RgOwnerEntraObjectIds $AllowedEntraUserIds `
    -TemplateFile (Join-Path $PSScriptRoot 'exercise.bicep') `
    -TemplateParameterObject @{
        workspaceName = $workspaceName
        acrName = $acrName
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
        workstationName = $workstationName
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

Invoke-K8sWorkstationSetup -SubscriptionId $SubscriptionId -ResourceGroupName $onpremGroupName `
    -LabPrefix $prefix -SetupScript (Get-K8sWorkstationScript) -Configuration $configuration

Invoke-MhhSynchronized -Name $lockName -ScriptBlock {
    Update-MhhToken | Out-Null
    Repair-K8sHubPeering -SubscriptionId $SubscriptionId -LabPrefix $prefix -SpokeVnetId $result.Outputs.spokeVnetId
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
@{ HackboxCredential = @{ name = 'Workstation VM'; value = $workstationName; note = $onpremGroupName } }
@{ HackboxCredential = @{ name = 'Workstation Resource ID'; value = $result.Outputs.workstationId; note = 'Connect using the shared Bastion' } }
@{ HackboxCredential = @{ name = 'K3s Master IP'; value = $masterIp; note = 'Private address; reachable from WSL on the workstation' } }
@{ HackboxCredential = @{ name = 'On-prem Resource Group'; value = $onpremGroupName; note = 'Four VMs, participant network and outbound NAT' } }
@{ HackboxCredential = @{ name = 'Arc Resource Group'; value = $ResourceGroupName; note = 'Exercise resources, ACR and Log Analytics' } }
@{ HackboxCredential = @{ name = 'Container Registry'; value = $exercise.Outputs.acrName; note = 'Use this name instead of the legacy <xy>mhacr example' } }
@{ HackboxCredential = @{ name = 'Log Analytics Workspace'; value = $exercise.Outputs.workspaceName; note = $ResourceGroupName } }
