$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$labRoot = Split-Path $PSScriptRoot -Parent
$subscription = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
$users = @(1..27 | ForEach-Object { '00000000-0000-0000-0000-{0:d12}' -f $_ })
$regions = @('swedencentral', 'australiaeast', 'indiasouthcentral', 'westindia', 'westus2')
$script:Assertions = 0

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAILED: $Message" }
    $script:Assertions++
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern)
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_ }
    Assert-Test ($null -ne $caught) "Expected failure: $Pattern"
    Assert-Test ($caught.ToString() -like "*$Pattern*") "Unexpected failure: $caught"
}

function Reset-Mock {
    param([int]$Count = 7)
    $global:ArcMock = @{
        users = @($users | Select-Object -First $Count)
        placement = @()
        vms = @()
        calls = [System.Collections.Generic.List[object]]::new()
        deployments = [System.Collections.Generic.List[object]]::new()
        registrations = @{}
        availableRegions = @($regions) + @('westeurope')
        quota = 100
        used = 0
        networkQuota = 100
        networkUsed = 0
        partialIps = @()
        restricted = $false
        missingSku = $false
        missingQuota = $false
        failCommand = ''
        failDeployment = $false
        wrongContext = $false
        cliSubscription = $subscription
        refreshes = 0
    }
}

function global:Update-MhhToken { $global:ArcMock.refreshes++ }
function global:Get-AzContext {
    $id = if ($global:ArcMock.wrongContext) { 'wrong' } else { $subscription }
    [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = $id } }
}
function global:New-MhhStablePassword {
    param([string]$Purpose)
    if ($Purpose -ne 'vm-admin') { throw 'Unexpected password purpose.' }
    'OfflineOnlyPassword123'
}
function global:New-AzSubscriptionDeployment {
    param($Name, $Location, $TemplateObject, $ErrorAction)
    if ($Name -ne 'microhack-arc-server-placement' -or $TemplateObject.resources.Count -ne 0) {
        throw 'Unexpected shared resources.'
    }
    $global:ArcMock.placement = @($TemplateObject.outputs.placement.value)
    [pscustomobject]@{ ProvisioningState = 'Succeeded' }
}
function global:New-AzResourceGroupDeployment {
    param($Name, $ResourceGroupName, $TemplateFile, $TemplateParameterObject, $ErrorAction)
    if ($global:ArcMock.failDeployment) { throw 'Mock ARM deployment failed.' }
    $template = Get-Content $TemplateFile -Raw | ConvertFrom-Json -AsHashtable
    foreach ($key in $template.parameters.Keys) {
        if (-not $TemplateParameterObject.ContainsKey($key)) { throw "Missing ARM parameter $key" }
    }
    foreach ($key in $TemplateParameterObject.Keys) {
        if (-not $template.parameters.ContainsKey($key)) { throw "Unknown ARM parameter $key" }
    }
    if ($TemplateParameterObject.adminPassword -isnot [securestring]) { throw 'Password must be secure.' }
    $global:ArcMock.deployments.Add($TemplateParameterObject)
    $global:ArcMock.vms += [pscustomobject]@{
        name = $TemplateParameterObject.virtualMachineName
        resourceGroup = $ResourceGroupName
        location = $TemplateParameterObject.location
        hardwareProfile = [pscustomobject]@{ vmSize = $TemplateParameterObject.virtualMachineSize }
        provisioningState = 'Succeeded'
        tags = [pscustomobject]@{}
    }
    [pscustomobject]@{ ProvisioningState = 'Succeeded' }
}

function Get-MockArgument {
    param([object[]]$Arguments, [string]$Name)
    $index = [array]::IndexOf($Arguments, $Name)
    if ($index -ge 0) { return $Arguments[$index + 1] }
    return ''
}

function global:az {
    $arguments = @($args)
    $global:LASTEXITCODE = 0
    $global:ArcMock.calls.Add($arguments)
    $command = $arguments[0..1] -join ' '
    if ($command -in @('account show', 'account list-locations')) {
        if ('--subscription' -in $arguments) {
            $global:LASTEXITCODE = 1
            return 'ERROR: unrecognized arguments: --subscription'
        }
    } elseif ((Get-MockArgument $arguments '--subscription') -ne $subscription) {
        throw 'Resource CLI calls must explicitly target the supplied subscription.'
    }
    if ($global:ArcMock.failCommand -and ($arguments -join ' ').Contains($global:ArcMock.failCommand)) {
        $global:LASTEXITCODE = 1
        return 'Mock CLI failure'
    }
    $value = switch ($command) {
        'account show' { $global:ArcMock.cliSubscription }
        'account list-locations' { $global:ArcMock.availableRegions }
        'deployment sub' {
            # Match Azure's nested projection: one deployment containing an array.
            return (ConvertTo-Json -InputObject @(
                if ($global:ArcMock.placement.Count -gt 0) { ,$global:ArcMock.placement }
            ) -Depth 30 -Compress)
        }
        'provider show' {
            $provider = Get-MockArgument $arguments '--namespace'
            @{ registrationState = if ($global:ArcMock.registrations.ContainsKey($provider)) {
                'Registered'
            } else { 'NotRegistered' } }
        }
        'provider register' {
            if ('--wait' -notin $arguments) { throw 'Must wait for registration.' }
            $global:ArcMock.registrations[(Get-MockArgument $arguments '--namespace')] = $true
            @{ registrationState = 'Registered' }
        }
        'group list' {
            @($global:ArcMock.users | ForEach-Object {
                @{ name = "rg-$($_.Substring($_.Length - 2))" }
            })
        }
        'group show' { @{ name = Get-MockArgument $arguments '--name' } }
        'role assignment' {
            @($global:ArcMock.users | ForEach-Object {
                @{
                    principalId = $_
                    roleDefinitionName = 'Owner'
                    scope = "/subscriptions/$subscription/resourceGroups/rg-$($_.Substring($_.Length - 2))"
                }
            })
        }
        'vm list' {
            $rg = Get-MockArgument $arguments '--resource-group'
            return (ConvertTo-Json -InputObject @(
                $global:ArcMock.vms | Where-Object { -not $rg -or $_.resourceGroup -eq $rg }
            ) -Depth 30 -Compress)
        }
        'vm list-skus' {
            @(
                foreach ($size in @('Standard_D2ads_v5', 'Standard_D4ads_v5')) {
                    if ($global:ArcMock.missingSku -and $size -eq 'Standard_D4ads_v5') { continue }
                    @{
                        name = $size
                        resourceType = 'virtualMachines'
                        family = 'standardDADSv5Family'
                        capabilities = @(@{ name = 'vCPUs'; value = if ($size -match '_D2') { '2' } else { '4' } })
                        restrictions = @(if ($global:ArcMock.restricted) { @{ type = 'Location' } })
                    }
                }
            )
        }
        'vm list-usage' {
            @(
                foreach ($name in @('cores', 'virtualMachines', 'standardDADSv5Family')) {
                    if ($global:ArcMock.missingQuota -and $name -eq 'standardDADSv5Family') { continue }
                    @{ name = @{ value = $name }; currentValue = $global:ArcMock.used; limit = $global:ArcMock.quota }
                }
            )
        }
        'network list-usages' {
            @('PublicIPAddresses', 'StandardSkuPublicIpAddresses') | ForEach-Object {
                @{ name = @{ value = $_ }; currentValue = $global:ArcMock.networkUsed; limit = $global:ArcMock.networkQuota }
            }
        }
        'vm show' {
            $name = Get-MockArgument $arguments '--name'
            $rg = Get-MockArgument $arguments '--resource-group'
            $global:ArcMock.vms | Where-Object { $_.name -eq $name -and $_.resourceGroup -eq $rg }
        }
        'vm update' {
            $name = Get-MockArgument $arguments '--name'
            $rg = Get-MockArgument $arguments '--resource-group'
            $vm = $global:ArcMock.vms | Where-Object { $_.name -eq $name -and $_.resourceGroup -eq $rg }
            $tag = (Get-MockArgument $arguments '--set') -split '=', 2
            $vm.tags | Add-Member -NotePropertyName ($tag[0] -replace '^tags\.', '') -NotePropertyValue $tag[1] -Force
            $vm
        }
        'vm run-command' {
            if ($arguments[2] -eq 'invoke' -and '--no-wait' -notin $arguments) { throw 'Linux must be asynchronous.' }
            if ($arguments[2] -eq 'create' -and (Get-MockArgument $arguments '--async-execution') -ne 'true') {
                throw 'Windows must be asynchronous.'
            }
            $file = if ($arguments[2] -eq 'invoke') {
                Get-MockArgument $arguments '--scripts'
            } else { Get-MockArgument $arguments '--script' }
            if (-not $file.StartsWith('@') -or -not (Test-Path $file.Substring(1))) {
                throw 'The original reconfiguration file must exist.'
            }
            @{ submitted = $true }
        }
        'network public-ip' {
            if ($arguments[2] -eq 'list') {
                return (ConvertTo-Json -InputObject @(
                    $global:ArcMock.partialIps
                    $global:ArcMock.vms | ForEach-Object {
                        @{ name = "$($_.name)-pip"; resourceGroup = $_.resourceGroup; location = $_.location }
                    }
                ) -Depth 30 -Compress)
            }
            @{ ipAddress = '203.0.113.10' }
        }
        default { throw "Unexpected CLI command: $($arguments -join ' ')" }
    }
    ConvertTo-Json -InputObject $value -Depth 30 -Compress
}

function Invoke-Shared {
    param([string]$Locations = ($regions -join ','))
    & (Join-Path $labRoot 'shared-deploy-lab.ps1') -SubscriptionId $subscription `
        -PreferredLocation $Locations -AllowedEntraUserIds $global:ArcMock.users
}

function Invoke-Lab {
    param(
        [string]$User = $users[0],
        [string]$Group = 'rg-01',
        [string]$Type = 'resourcegroup',
        [string[]]$Locations = $regions
    )
    & (Join-Path $labRoot 'deploy-lab.ps1') -DeploymentType $Type -SubscriptionId $subscription `
        -ResourceGroupName $Group -PreferredLocation $Locations -AllowedEntraUserIds @($User)
}

foreach ($file in Get-ChildItem $labRoot -Filter '*.ps1' -Recurse) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-Test ($errors.Count -eq 0) "PowerShell parsing: $($file.Name): $errors"
}
$defaults = Get-Content (Join-Path $labRoot 'lab-defaults.json') -Raw | ConvertFrom-Json -AsHashtable
Assert-Test ($defaults.deploymentType -eq 'resourcegroup') 'Resource group isolation'
Assert-Test ($defaults.groups.Count -eq 0) 'No extra licenses'
Assert-Test (-not $defaults.ContainsKey('labsPerSubscription')) 'Console controls subscription packing'
Assert-Test (-not $defaults.ContainsKey('estimatedDailyCostsUsd')) 'No invented cost estimate'
$source = Get-Content (Join-Path (Split-Path $labRoot -Parent) 'resources\demo-vm-creator\create_vms.sh') -Raw
$bashRegions = [regex]::Match($source, '(?m)^regions=\(([^)]+)\)').Groups[1].Value
$bashRegions = @([regex]::Matches($bashRegions, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
Assert-Test (($bashRegions -join ',') -eq ($regions -join ',')) 'Regions match verified Bash'
Assert-Test (($defaults.preferredLocation -replace '\s', '') -eq ($regions -join ',')) 'Defaults preserve region order'
Assert-Test ($source -match 'virtualWinMachineSize="Standard_D4ads_v5"') 'Windows SKU matches Bash'
Assert-Test ($source -match 'virtualLnxMachineSize="Standard_D2ads_v5"') 'Linux SKU matches Bash'

Reset-Mock
Invoke-Shared
Assert-Test ($global:ArcMock.placement.Count -eq 7) 'All Console participants mapped'
Assert-Test ($global:ArcMock.placement[5].location -eq $regions[0]) 'Round-robin wraps'
Assert-Test ($global:ArcMock.registrations.Count -eq 15) 'Providers registered once'
$global:ArcMock.users = @($global:ArcMock.users | Sort-Object -Descending)
Invoke-Shared
Assert-Test ($global:ArcMock.placement[0].userId -eq $users[0]) 'Input ordering does not affect placement'

$credentials = @(Invoke-Lab)
Assert-Test ($global:ArcMock.deployments.Count -eq 2) 'Exactly two VMs, no Windows 2012'
Assert-Test ($global:ArcMock.deployments[0].virtualMachineSize -eq 'Standard_D2ads_v5') 'Linux size'
Assert-Test ($global:ArcMock.deployments[1].virtualMachineSize -eq 'Standard_D4ads_v5') 'Windows size'
Assert-Test ($global:ArcMock.deployments[0].networkSecurityGroupRules[0].properties.destinationPortRange -eq '22') 'Existing SSH rule'
Assert-Test ($global:ArcMock.deployments[1].networkSecurityGroupRules.Count -eq 2) 'Existing RDP/WinRM rules'
Assert-Test ($credentials.Count -eq 5) 'Only dashboard credentials on success stream'
Assert-Test ($credentials[-1].HackboxCredential.value -like '*NOT verified*') 'Honest asynchronous status'
Assert-Test ($credentials[1].HackboxCredential.value -eq 'OfflineOnlyPassword123') 'Per-lab password returned after acceptance'
$runs = @($global:ArcMock.calls | Where-Object { $_[0] -eq 'vm' -and $_[1] -eq 'run-command' }).Count
Invoke-Lab | Out-Null
Assert-Test ($global:ArcMock.deployments.Count -eq 2) 'Rerun skips existing VMs'
Assert-Test (@($global:ArcMock.calls | Where-Object { $_[0] -eq 'vm' -and $_[1] -eq 'run-command' }).Count -eq $runs) 'Rerun does not contact stopped agents'
Invoke-Shared
Assert-Test ($global:ArcMock.placement.Count -eq 7) 'Shared rerun accounts for existing VMs'
Invoke-Lab -User $users[1] -Group 'rg-02' | Out-Null
Assert-Test ($global:ArcMock.deployments[-1].location -eq 'australiaeast') 'Second participant gets next region'
Reset-Mock -Count 27
Invoke-Shared
Assert-Test ($global:ArcMock.placement.Count -eq 27) 'No hardcoded participant default or maximum'

Reset-Mock -Count 1
$global:ArcMock.quota = 6
Invoke-Shared
Assert-Test ($global:ArcMock.placement.Count -eq 1) 'Exact six-core family threshold passes'
Reset-Mock -Count 1
$global:ArcMock.quota = 5
Assert-Throws { Invoke-Shared } 'Insufficient quota'
Assert-Test ($global:ArcMock.placement.Count -eq 0) 'Quota failure cannot publish placement'
Reset-Mock -Count 1
$global:ArcMock.quota = 7
$global:ArcMock.used = 2
Assert-Throws { Invoke-Shared } 'Insufficient quota'
Reset-Mock -Count 1
$global:ArcMock.networkQuota = 1
Assert-Throws { Invoke-Shared } 'Insufficient quota'
Reset-Mock -Count 1
$global:ArcMock.networkQuota = 2
$global:ArcMock.networkUsed = 1
$global:ArcMock.partialIps = @(@{
    name = 'vm-linux-mh-pip'; resourceGroup = 'rg-01'; location = 'swedencentral'
})
Invoke-Shared
Assert-Test ($global:ArcMock.placement.Count -eq 1) 'Partial deployment does not double-count existing public IPs'
Reset-Mock -Count 1
$global:ArcMock.restricted = $true
Assert-Throws { Invoke-Shared } 'restricted'
Reset-Mock -Count 1
$global:ArcMock.missingSku = $true
Assert-Throws { Invoke-Shared } 'not available'
Reset-Mock -Count 1
$global:ArcMock.missingQuota = $true
Assert-Throws { Invoke-Shared } 'Cannot verify quota'
Reset-Mock -Count 1
Assert-Throws { Invoke-Lab } 'Run shared-deploy-lab.ps1'
Reset-Mock -Count 1
$global:ArcMock.wrongContext = $true
Assert-Throws { Invoke-Shared } 'already be authenticated'
Assert-Test ($global:ArcMock.calls.Count -eq 0) 'Wrong context fails without CLI access'
Reset-Mock -Count 1
$global:ArcMock.cliSubscription = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
Assert-Throws { Invoke-Shared } 'Azure CLI must already have SubscriptionId selected'
Assert-Throws { Invoke-Lab } 'Azure CLI must already have SubscriptionId selected'
Assert-Test (@($global:ArcMock.calls | Where-Object {
    ($_[0..1] -join ' ') -ne 'account show'
}).Count -eq 0) 'Wrong active CLI subscription fails before region queries or subscription changes'
Assert-Test ($global:ArcMock.registrations.Count -eq 0) 'Wrong CLI subscription cannot register providers'
Reset-Mock -Count 1
$global:ArcMock.failCommand = 'account show'
Assert-Throws { Invoke-Shared } 'Azure CLI failed'
Reset-Mock -Count 1
$global:ArcMock.failCommand = 'provider show'
Assert-Throws { Invoke-Shared } 'Azure CLI failed'
Reset-Mock -Count 1
Invoke-Shared
$global:ArcMock.failDeployment = $true
Assert-Throws { Invoke-Lab } 'Mock ARM deployment failed'
Assert-Test ($global:ArcMock.vms.Count -eq 0) 'Failed deployment publishes no credentials or reconfiguration'
Reset-Mock -Count 1
Invoke-Shared
$global:ArcMock.failCommand = 'vm run-command'
Assert-Throws { Invoke-Lab } 'Azure CLI failed'
Assert-Test ($global:ArcMock.vms[0].tags.microhackReconfiguration -eq 'submitting') 'Ambiguous submission preserved'
$global:ArcMock.failCommand = ''
Assert-Throws { Invoke-Lab } 'interrupted'
Reset-Mock -Count 1
Invoke-Shared
Invoke-Lab | Out-Null
$global:ArcMock.vms[0].tags.microhackArcUserId = $users[1]
Assert-Throws { Invoke-Lab } 'not marked as belonging'
$global:ArcMock.vms[0].tags.microhackArcUserId = $users[0]
$global:ArcMock.vms[0].location = 'westus2'
Assert-Throws { Invoke-Lab } 'No VM will be moved'
Assert-Throws { Invoke-Lab -Type subscription } 'requires resourcegroup'
Assert-Throws { Invoke-Lab -Group 'rg-someone-else' } 'not owned'
Reset-Mock -Count 2
Invoke-Shared
$global:ArcMock.users = @($users[1])
Assert-Throws { Invoke-Shared } 'remove or relocate'
Reset-Mock -Count 1
$global:ArcMock.users = @($users[0], $users[0])
Assert-Throws { Invoke-Shared } 'duplicate'
Reset-Mock -Count 0
Assert-Throws { Invoke-Shared } 'at least one'
Reset-Mock -Count 1
Assert-Throws { Invoke-Shared -Locations '' } 'empty string'
Assert-Throws { Invoke-Shared -Locations ' ' } 'at least one non-empty'
Assert-Throws { Invoke-Lab -Locations @() } 'at least one non-empty'
Assert-Throws { Invoke-Shared -Locations 'swedencentral,' } 'at least one non-empty'
Assert-Throws { Invoke-Shared -Locations 'swedencentral, SwedenCentral' } 'duplicate Azure regions'
Assert-Throws { Invoke-Shared -Locations 'not-an-azure-region' } 'Unknown Azure region'
Assert-Test ($global:ArcMock.registrations.Count -eq 0) 'Invalid region input fails before subscription changes'
Assert-Test ($global:ArcMock.placement.Count -eq 0) 'Invalid regions never publish placement'
Reset-Mock -Count 1
$global:ArcMock.failCommand = 'account list-locations'
Assert-Throws { Invoke-Shared } 'Azure CLI failed'

Reset-Mock
$withoutIndia = @($regions | Where-Object { $_ -ne 'indiasouthcentral' })
Invoke-Shared -Locations ($withoutIndia -join ',')
Assert-Test (($global:ArcMock.placement.location -join ',') -eq (
    'swedencentral,australiaeast,westindia,westus2,swedencentral,australiaeast,westindia'
)) 'Console removal of indiasouthcentral controls round-robin and wraparound'
Assert-Test (@($global:ArcMock.calls | Where-Object {
    $_[0] -eq 'vm' -and $_[1] -eq 'list-skus' -and 'indiasouthcentral' -in $_
}).Count -eq 0) 'Removed region is not checked or selected for VM deployment'
Invoke-Lab -User $users[2] -Group 'rg-03' -Locations $withoutIndia | Out-Null
Assert-Test ($global:ArcMock.deployments.Count -eq 2) 'Filtered Console list deploys two participant VMs'
Assert-Test (@($global:ArcMock.deployments | Where-Object { $_.location -ne 'westindia' }).Count -eq 0) 'Both VMs use the filtered Console mapping'

Reset-Mock -Count 3
Invoke-Shared -Locations ' WestUS2, SwedenCentral '
Assert-Test (($global:ArcMock.placement.location -join ',') -eq 'westus2,swedencentral,westus2') 'Console order wins over defaults and names are normalized'
Invoke-Lab -Locations @(' WestUS2 ', ' SwedenCentral ') | Out-Null
Assert-Test ($global:ArcMock.deployments[0].location -eq 'westus2') 'Participant hook accepts Console region arrays'
Assert-Throws { Invoke-Shared -Locations 'swedencentral,westus2' } 'remove or relocate'

Reset-Mock -Count 3
Invoke-Shared -Locations 'westeurope'
Assert-Test (($global:ArcMock.calls[0][0..1] -join ' ') -eq 'account show') 'Active CLI subscription is checked first'
Assert-Test (($global:ArcMock.calls[1][0..1] -join ' ') -eq 'account list-locations') 'Region catalog query follows context verification'
Assert-Test (@($global:ArcMock.calls | Where-Object {
    $_[0] -eq 'account' -and '--subscription' -in $_
}).Count -eq 0) 'Account commands use the verified current context without subscription arguments'
Assert-Test (@($global:ArcMock.placement | Where-Object { $_.location -ne 'westeurope' }).Count -eq 0) 'Console can select a valid region absent from defaults'
Invoke-Lab -Locations @('westeurope') | Out-Null
Assert-Test ($global:ArcMock.deployments[1].location -eq 'westeurope') 'Single Console region works in both hooks'
Reset-Mock -Count 1
$global:ArcMock.restricted = $true
Assert-Throws { Invoke-Shared -Locations 'westeurope' } 'restricted'

Write-Host "PASS: $script:Assertions offline assertions. No Azure login or network calls were made."
