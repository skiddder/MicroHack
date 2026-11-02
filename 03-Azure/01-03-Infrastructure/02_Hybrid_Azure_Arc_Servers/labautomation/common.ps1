$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:ArcPlacementDeployment = 'microhack-arc-server-placement'
$script:ArcVmSource = Join-Path (Split-Path $PSScriptRoot -Parent) 'resources\demo-vm-creator'
$script:ArcVmSizes = @{ linux = 'Standard_D2ads_v5'; win2025 = 'Standard_D4ads_v5' }
$script:ArcVmTypes = @('linux', 'win2025')

function Invoke-ArcAz {
    param([Parameter(Mandatory)][string[]]$Arguments)

    Update-MhhToken | Out-Null
    $PSNativeCommandUseErrorActionPreference = $false
    $scopeArguments = @('--subscription', $SubscriptionId)
    if ($Arguments[0] -eq 'account' -and $Arguments[1] -in @('show', 'list-locations')) {
        # Inspect the isolated current context; list-locations has no subscription option.
        $scopeArguments = @()
    }
    $result = & az @Arguments @scopeArguments --only-show-errors --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed ($($Arguments[0..1] -join ' ')): $($result -join [Environment]::NewLine)"
    }
    $text = $result -join [Environment]::NewLine
    if (-not [string]::IsNullOrWhiteSpace($text)) {
        $text | ConvertFrom-Json -Depth 100
    }
}

function Assert-ArcContext {
    $context = Get-AzContext
    if (-not $context -or $context.Subscription.Id -ne $SubscriptionId) {
        throw 'Az PowerShell must already be authenticated to SubscriptionId. The Hackbox Console supplies this context; this script never logs in.'
    }
    $cliSubscription = Invoke-ArcAz -Arguments @('account', 'show', '--query', 'id')
    if ($cliSubscription -ne $SubscriptionId) {
        throw 'Azure CLI must already have SubscriptionId selected in its isolated context. This script never switches subscriptions.'
    }
}

function Get-ArcRegions {
    param([string[]]$Locations)

    $regions = @($Locations | ForEach-Object { ([string]$_).Split(',') } |
        ForEach-Object { $_.Trim().ToLowerInvariant() })
    if ($regions.Count -eq 0 -or '' -in $regions) {
        throw 'The Console must supply at least one non-empty Azure region in PreferredLocation.'
    }
    if (@($regions | Sort-Object -Unique).Count -ne $regions.Count) {
        throw 'PreferredLocation contains duplicate Azure regions.'
    }
    $available = @(Invoke-ArcAz -Arguments @('account', 'list-locations', '--query', '[].name'))
    foreach ($region in $regions) {
        if ($region -notin $available) {
            throw "Unknown Azure region '$region' for this subscription. Use programmatic names from az account list-locations."
        }
    }
    return $regions
}

function Get-ArcPlacement {
    $deployments = @(Invoke-ArcAz -Arguments @(
        'deployment', 'sub', 'list', '--query',
        "[?name=='$script:ArcPlacementDeployment'].properties.outputs.placement.value"
    ))
    if ($deployments.Count -gt 1) {
        throw 'Multiple Arc placement records were returned.'
    }
    if ($deployments.Count -eq 1) {
        return $deployments[0]
    }
}

function New-ArcPlacement {
    param([string[]]$UserIds, [string[]]$Regions)

    if ($UserIds.Count -eq 0) {
        throw 'The Console must supply at least one participant.'
    }
    $users = @($UserIds | ForEach-Object { ([guid]$_).ToString() } | Sort-Object -Unique)
    if ($users.Count -ne $UserIds.Count) {
        throw 'The participant list contains duplicate user IDs.'
    }
    for ($i = 0; $i -lt $users.Count; $i++) {
        [pscustomobject]@{
            userId = $users[$i]
            location = $Regions[$i % $Regions.Count]
        }
    }
}

function Assert-ArcQuota {
    param([object[]]$Usages, [string]$Name, [int]$Additional, [string]$Location)

    $usage = @($Usages | Where-Object { $_.name.value -eq $Name })
    if ($usage.Count -ne 1) {
        throw "Cannot verify quota '$Name' in $Location."
    }
    $needed = [int]$usage[0].currentValue + $Additional
    if ($needed -gt [int]$usage[0].limit) {
        throw "Insufficient quota '$Name' in ${Location}: current=$($usage[0].currentValue), additional=$Additional, limit=$($usage[0].limit). Ask the coach to resolve the quota; no SKU or region will be substituted."
    }
    Write-Host "Quota $Location/$Name verified: $needed / $($usage[0].limit)."
}

function Test-ArcCapacity {
    param([object[]]$Placement)

    $vms = @(Invoke-ArcAz -Arguments @('vm', 'list'))
    $publicIps = @(Invoke-ArcAz -Arguments @('network', 'public-ip', 'list'))
    $groups = @(Invoke-ArcAz -Arguments @('group', 'list'))
    $assignments = @(Invoke-ArcAz -Arguments @('role', 'assignment', 'list', '--all', '--fill-principal-name', 'false'))
    $owners = @($assignments | Where-Object {
        $_.roleDefinitionName -eq 'Owner' -and $_.scope -match '(?i)/resourceGroups/[^/]+$'
    })
    $remaining = @{}
    $remainingIps = @{}
    foreach ($entry in $Placement) {
        $ownedGroups = @($owners | Where-Object { $_.principalId -eq $entry.userId } |
            ForEach-Object { ($_.scope -split '/')[-1] } | Sort-Object -Unique)
        if ($ownedGroups.Count -ne 1) {
            throw "Expected exactly one Console-provisioned Owner resource group for user $($entry.userId); found $($ownedGroups.Count)."
        }
        $groupName = $ownedGroups[0]
        if (@($groups | Where-Object { $_.name -eq $groupName }).Count -ne 1) {
            throw "Participant resource group '$groupName' was not found."
        }
        foreach ($type in $script:ArcVmTypes) {
            $existingIp = @($publicIps | Where-Object {
                $_.resourceGroup -eq $groupName -and $_.name -eq "vm-$type-mh-pip"
            })
            if ($existingIp.Count -gt 0 -and $existingIp[0].location -ne $entry.location) {
                throw "Existing public IP in '$groupName' does not match its assigned region."
            }
            if ($existingIp.Count -eq 0) {
                if (-not $remainingIps.ContainsKey($entry.location)) { $remainingIps[$entry.location] = 0 }
                $remainingIps[$entry.location]++
            }
            $existing = @($vms | Where-Object {
                $_.resourceGroup -eq $groupName -and $_.name -eq "vm-$type-mh"
            })
            if ($existing.Count -gt 0) {
                Assert-ArcVm -Vm $existing[0] -Location $entry.location -Size $script:ArcVmSizes[$type] -UserId $entry.userId
            } else {
                $key = "$($entry.location)/$type"
                if (-not $remaining.ContainsKey($key)) { $remaining[$key] = 0 }
                $remaining[$key]++
            }
        }
    }

    foreach ($location in @($Placement.location | Sort-Object -Unique)) {
        $skus = @(Invoke-ArcAz -Arguments @('vm', 'list-skus', '--location', $location, '--all'))
        $usages = @(Invoke-ArcAz -Arguments @('vm', 'list-usage', '--location', $location))
        $familyCores = @{}
        $totalCores = 0
        $vmCount = 0
        foreach ($type in $script:ArcVmTypes) {
            $size = $script:ArcVmSizes[$type]
            $sku = @($skus | Where-Object { $_.resourceType -eq 'virtualMachines' -and $_.name -eq $size })
            if ($sku.Count -ne 1) {
                throw "SKU $size is not available in $location."
            }
            if (@($sku[0].restrictions | Where-Object { $_.type -eq 'Location' }).Count -gt 0) {
                throw "SKU $size is restricted in $location for this subscription."
            }
            $cores = @($sku[0].capabilities | Where-Object { $_.name -eq 'vCPUs' })
            if ($cores.Count -ne 1 -or [int]$cores[0].value -le 0 -or -not $sku[0].family) {
                throw "Cannot determine CPU quota requirements for $size in $location."
            }
            $count = 0
            if ($remaining.ContainsKey("$location/$type")) { $count = $remaining["$location/$type"] }
            $additional = $count * [int]$cores[0].value
            $family = $sku[0].family
            if (-not $familyCores.ContainsKey($family)) { $familyCores[$family] = 0 }
            $familyCores[$family] += $additional
            $totalCores += $additional
            $vmCount += $count
        }
        Assert-ArcQuota -Usages $usages -Name 'cores' -Additional $totalCores -Location $location
        Assert-ArcQuota -Usages $usages -Name 'virtualMachines' -Additional $vmCount -Location $location
        foreach ($family in $familyCores.Keys) {
            Assert-ArcQuota -Usages $usages -Name $family -Additional $familyCores[$family] -Location $location
        }
        $networkUsages = @(Invoke-ArcAz -Arguments @('network', 'list-usages', '--location', $location))
        $ipCount = 0
        if ($remainingIps.ContainsKey($location)) { $ipCount = $remainingIps[$location] }
        Assert-ArcQuota -Usages $networkUsages -Name 'PublicIPAddresses' -Additional $ipCount -Location $location
        Assert-ArcQuota -Usages $networkUsages -Name 'StandardSkuPublicIpAddresses' -Additional $ipCount -Location $location
    }
}

function Assert-ArcVm {
    param([object]$Vm, [string]$Location, [string]$Size, [string]$UserId = '')

    if ($UserId -and (
        -not $Vm.PSObject.Properties['tags'] -or -not $Vm.tags -or
        -not $Vm.tags.PSObject.Properties['microhackArcUserId'] -or
        $Vm.tags.microhackArcUserId -ne $UserId
    )) {
        throw "Existing VM '$($Vm.name)' is not marked as belonging to this participant's automation. The coach must verify its origin and credentials before reuse."
    }
    if ($Vm.location -ne $Location -or $Vm.hardwareProfile.vmSize -ne $Size) {
        throw "Existing VM '$($Vm.name)' does not match assigned location/SKU. No VM will be moved or resized automatically."
    }
    if ($Vm.provisioningState -ne 'Succeeded') {
        throw "Existing VM '$($Vm.name)' is not successfully provisioned: $($Vm.provisioningState). Resolve this before retrying."
    }
}
