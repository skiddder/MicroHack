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
Assert-ArcAssets
Assert-ArcContext
if ($DeploymentType -notin @('resourcegroup', 'resourcegroup-with-subscriptionowner') -or
    [string]::IsNullOrWhiteSpace($ResourceGroupName)) {
    throw 'This lab requires resourcegroup or resourcegroup-with-subscriptionowner deployment into the resource group supplied by the Console.'
}
if ($AllowedEntraUserIds.Count -ne 1) {
    throw 'Exactly one participant per resource group is required.'
}
$regions = @(Get-ArcRegions -Locations $PreferredLocation)
$userId = ([guid]$AllowedEntraUserIds[0]).ToString()
$placement = @(Get-ArcPlacement | Where-Object { $_.userId -eq $userId })
if ($placement.Count -ne 1 -or $placement[0].location -notin $regions) {
    throw 'No valid placement exists for this participant. Run shared-deploy-lab.ps1 successfully first.'
}
$location = $placement[0].location
$ownerScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
$owners = @(Invoke-ArcAz -Arguments @(
    'role', 'assignment', 'list', '--all', '--fill-principal-name', 'false'
))
$directOwner = @($owners | Where-Object {
    $_.principalId -eq $userId -and $_.roleDefinitionName -eq 'Owner' -and $_.scope -eq $ownerScope
}).Count -gt 0
if ($DeploymentType -eq 'resourcegroup-with-subscriptionowner') {
    if (@($owners | Where-Object {
        $_.principalId -eq $userId -and $_.roleDefinitionName -eq 'Owner' -and $_.scope -eq "/subscriptions/$SubscriptionId"
    }).Count -eq 0) {
        throw "Participant '$userId' has no visible Owner assignment on subscription '$SubscriptionId'. Verify Console RBAC provisioning and propagation."
    }
} elseif (-not $directOwner) {
    throw "The requested resource group '$ResourceGroupName' is not owned by this participant through a visible direct Owner assignment (user $userId). The resourcegroup mode requires direct RG ownership."
}
$azureGroup = Invoke-ArcAz -Arguments @('group', 'show', '--name', $ResourceGroupName)
Assert-ArcAzureResourceGroup -Group $azureGroup -ResourceGroupName $ResourceGroupName -UserId $userId
Assert-ArcAzureGroupLayout -AzureResourceGroupName $ResourceGroupName -Vms @(
    Invoke-ArcAz -Arguments @('vm', 'list', '--resource-group', $ResourceGroupName)
)
Set-ArcResourceGroupSecurityTag -ResourceGroupName $ResourceGroupName -AdditionalTags @{
    microhackArcPurpose = 'azure'
    microhackArcUserId = $userId
}
$onPremResourceGroupName = Initialize-ArcOnPremResourceGroup -AzureResourceGroupName $ResourceGroupName `
    -UserId $userId -Location $location
$vmScope = "/subscriptions/$SubscriptionId/resourceGroups/$onPremResourceGroupName"
$password = New-MhhStablePassword -Purpose 'vm-admin'
$existingVms = @(Invoke-ArcAz -Arguments @('vm', 'list', '--resource-group', $onPremResourceGroupName))
$endpoints = @()

foreach ($type in $script:ArcVmTypes) {
    $vmName = "vm-$type-mh"
    $vmResourceId = "$vmScope/providers/Microsoft.Compute/virtualMachines/$vmName"
    $vm = @($existingVms | Where-Object { $_.name -eq $vmName })
    $isNewVm = $vm.Count -eq 0
    if ($isNewVm) {
        $parameterDocument = Get-Content (Join-Path $script:ArcVmSource "parameters-$type.json") -Raw |
            ConvertFrom-Json -AsHashtable
        $parameters = @{}
        foreach ($key in $parameterDocument.parameters.Keys) {
            $parameters[$key] = $parameterDocument.parameters[$key].value
        }
        $parameters.location = $location
        $parameters.virtualMachineName = $vmName
        $parameters.virtualMachineComputerName = $vmName
        $parameters.virtualMachineRG = $onPremResourceGroupName
        $parameters.virtualMachineSize = $script:ArcVmSizes[$type]
        $parameters.adminUsername = 'mhadmin'
        $parameters.adminPassword = $password
        $parameters.networkInterfaceName = "$vmName-nic"
        $parameters.networkSecurityGroupName = "$vmName-nsg"
        $parameters.virtualNetworkName = "$vmName-vnet"
        $parameters.publicIpAddressName = "$vmName-pip"

        Update-MhhToken | Out-Null
        $result = New-AzResourceGroupDeployment -Name "$vmName-Deploy" `
            -ResourceGroupName $onPremResourceGroupName `
            -TemplateFile (Join-Path $script:ArcVmSource "template-$type.json") `
            -TemplateParameterObject $parameters -ErrorAction Stop
        if ($result.ProvisioningState -ne 'Succeeded') {
            throw "Deployment of $vmName failed: $($result.ProvisioningState)."
        }
        $vm = @(Invoke-ArcAz -Arguments @('vm', 'show', '--resource-group', $onPremResourceGroupName, '--name', $vmName))
    }
    $vm = @(Wait-ArcVmProvisioning -Vm $vm[0] -Location $location -Size $script:ArcVmSizes[$type] -UserId $userId -AllowUnmarked)
    if ((Get-ArcVmUserId -Vm $vm[0]) -eq '') {
        if (-not $isNewVm) {
            Write-Warning "Adding missing ownership tag to existing VM '$vmName' in '$onPremResourceGroupName' under the approved reuse policy. Its origin and password are not verified; the password is not reset."
        }
        Invoke-ArcAz -Arguments @(
            'tag', 'update', '--resource-id', $vmResourceId, '--operation', 'Merge',
            '--tags', "microhackArcUserId=$userId"
        ) | Out-Null
        $vm = @(Invoke-ArcAz -Arguments @(
            'vm', 'show', '--resource-group', $onPremResourceGroupName, '--name', $vmName
        ))
    }
    $vm = @(Wait-ArcVmProvisioning -Vm $vm[0] -Location $location -Size $script:ArcVmSizes[$type] -UserId $userId)
    $state = ''
    if ($vm[0].tags -and $vm[0].tags.PSObject.Properties['microhackReconfiguration']) {
        $state = $vm[0].tags.microhackReconfiguration
    }
    if ($state -eq 'submitting') {
        throw "The previous reconfiguration submission for $vmName was interrupted. The coach must inspect the VM before clearing its microhackReconfiguration tag."
    }
    if ($state -notin @('', 'submitted')) {
        throw "Unknown reconfiguration state '$state' on $vmName."
    }
    if ($state -ne 'submitted') {
        # A stopped guest agent cannot reliably accept a second run-command.
        Invoke-ArcAz -Arguments @(
            'tag', 'update', '--resource-id', $vmResourceId, '--operation', 'Merge',
            '--tags', 'microhackReconfiguration=submitting'
        ) | Out-Null
        if ($type -eq 'linux') {
            Invoke-ArcAz -Arguments @(
                'vm', 'run-command', 'invoke', '--resource-group', $onPremResourceGroupName, '--name', $vmName,
                '--command-id', 'RunShellScript', '--scripts',
                ('@' + (Join-Path $script:ArcVmSource 'reconfig-ubuntu.sh')), '--no-wait'
            ) | Out-Null
        } else {
            Invoke-ArcAz -Arguments @(
                'vm', 'run-command', 'create', '--resource-group', $onPremResourceGroupName, '--vm-name', $vmName,
                '--name', 'reconfigWin', '--location', $location, '--script',
                ('@' + (Join-Path $script:ArcVmSource 'reconfig-win.ps1')), '--async-execution', 'true'
            ) | Out-Null
        }
        Invoke-ArcAz -Arguments @(
            'tag', 'update', '--resource-id', $vmResourceId, '--operation', 'Merge',
            '--tags', 'microhackReconfiguration=submitted'
        ) | Out-Null
    }
    $ip = Invoke-ArcAz -Arguments @(
        'network', 'public-ip', 'show', '--resource-group', $onPremResourceGroupName, '--name', "$vmName-pip"
    )
    if ([string]::IsNullOrWhiteSpace($ip.ipAddress)) {
        throw "No public IP address was returned for $vmName."
    }
    $endpoints += @{ name = $vmName; ip = $ip.ipAddress; type = $type }
}

@{ HackboxCredential = @{ name = 'VM Admin Username'; value = 'mhadmin'; note = "Both simulated on-prem VMs in $onPremResourceGroupName" } }
@{ HackboxCredential = @{ name = 'VM Admin Password'; value = $password; note = 'Stable per-user credential for both VMs' } }
foreach ($endpoint in $endpoints) {
    $protocol = if ($endpoint.type -eq 'linux') { 'SSH port 22' } else { 'RDP port 3389; WinRM port 5985' }
    @{ HackboxCredential = @{
        name = $endpoint.name
        value = $endpoint.ip
        note = "$protocol; Azure region: $location; resource group: $onPremResourceGroupName"
    } }
}
@{ HackboxCredential = @{
    name = 'Azure exercise resource group'
    value = $ResourceGroupName
    note = 'Onboard Arc machines and create workspaces, DCRs, policies and other exercise resources here.'
} }
@{ HackboxCredential = @{
    name = 'Simulated on-prem resource group'
    value = $onPremResourceGroupName
    note = 'Underlying Azure VMs and their infrastructure only; do not use this group for Arc onboarding.'
} }
@{ HackboxCredential = @{
    name = 'Reconfiguration status'
    value = 'Submitted asynchronously - completion NOT verified'
    note = 'Connect using SSH/RDP and verify guest-agent shutdown and IMDS blocking before Arc onboarding. Windows may reboot. No VM is onboarded to Arc yet.'
} }
Write-Warning 'Reconfiguration was only submitted, not verified. Check both guests before starting challenge 1.'
