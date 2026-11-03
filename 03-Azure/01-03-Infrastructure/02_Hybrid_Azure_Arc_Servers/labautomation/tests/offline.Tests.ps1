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
        groupTags = @{}
        invalidGroupTagResponse = $false
        calls = [System.Collections.Generic.List[object]]::new()
        deployments = [System.Collections.Generic.List[object]]::new()
        vmTemplatePaths = [System.Collections.Generic.List[string]]::new()
        sharedTemplatePaths = [System.Collections.Generic.List[string]]::new()
        sharedTemplates = [System.Collections.Generic.List[object]]::new()
        sharedFailure = ''
        sharedLocation = ''
        otherResources = @()
        inventoryShape = 'valid'
        registrations = @{}
        availableRegions = @($regions) + @('westeurope')
        quota = 100
        used = 0
        networkQuota = '1000'
        networkUsed = '0'
        totalNetworkQuota = '1000'
        totalNetworkUsed = '0'
        missingNetworkQuota = $false
        duplicateNetworkQuota = $false
        networkUsages = @(Get-Content (Join-Path $PSScriptRoot 'fixtures\network-usages.json') -Raw | ConvertFrom-Json)
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
    [CmdletBinding()]
    param([string]$Name, [string]$Location, [Parameter(Mandatory)][string]$TemplateFile)

    $global:ArcMock.sharedTemplatePaths.Add($TemplateFile)
    if (-not (Test-Path -LiteralPath $TemplateFile) -or [System.IO.Path]::GetExtension($TemplateFile) -ne '.json') {
        throw 'Shared deployment must receive an existing JSON template file.'
    }
    $template = Get-Content -LiteralPath $TemplateFile -Raw | ConvertFrom-Json -AsHashtable
    $global:ArcMock.sharedTemplates.Add($template)
    if ($Name -ne 'microhack-arc-server-placement' -or $template.resources.Count -ne 0) {
        throw 'Unexpected shared resources.'
    }
    if ($template.outputs.placement.type -ne 'array' -or $template.outputs.placement.value -isnot [array]) {
        throw 'Placement output must be a JSON array, including for a single participant.'
    }
    foreach ($entry in $template.outputs.placement.value) {
        if ($entry.userId -isnot [string] -or $entry.location -isnot [string] -or $entry.Count -ne 2) {
            throw 'Placement entries must contain only plain userId and location strings.'
        }
    }
    if ($global:ArcMock.sharedFailure -eq 'throw') { throw 'Mock shared deployment failed.' }
    if ($global:ArcMock.sharedFailure -eq 'state') {
        return [pscustomobject]@{ ProvisioningState = 'Failed' }
    }
    if ($global:ArcMock.sharedLocation -and $Location -ne $global:ArcMock.sharedLocation) {
        throw 'Existing subscription deployment location cannot be changed.'
    }
    $global:ArcMock.sharedLocation = $Location
    $global:ArcMock.placement = @($template.outputs.placement.value | ForEach-Object { [pscustomobject]$_ })
    [pscustomobject]@{ ProvisioningState = 'Succeeded' }
}
function global:New-AzResourceGroupDeployment {
    param($Name, $ResourceGroupName, $TemplateFile, $TemplateParameterObject, $ErrorAction)
    if ($global:ArcMock.failDeployment) { throw 'Mock ARM deployment failed.' }
    if (-not $global:ArcMock.groupTags.ContainsKey($ResourceGroupName) -or
        $global:ArcMock.groupTags[$ResourceGroupName].SecurityControl -cne 'Ignore') {
        throw 'VM deployment requires SecurityControl=Ignore on its resource group first.'
    }
    $global:ArcMock.vmTemplatePaths.Add($TemplateFile)
    $template = Get-Content $TemplateFile -Raw | ConvertFrom-Json -AsHashtable
    foreach ($key in $template.parameters.Keys) {
        if (-not $TemplateParameterObject.ContainsKey($key)) { throw "Missing ARM parameter $key" }
    }
    foreach ($key in $TemplateParameterObject.Keys) {
        if (-not $template.parameters.ContainsKey($key)) { throw "Unknown ARM parameter $key" }
    }
    if ($TemplateParameterObject.adminPassword -is [securestring]) {
        throw 'Unable to serialize secure string value'
    }
    if ($TemplateParameterObject.adminPassword -isnot [string]) {
        throw 'Password must be a serializable in-memory string.'
    }
    if ($template.parameters.adminPassword.type -ine 'secureString') {
        throw 'ARM must retain the secureString password parameter type.'
    }
    $serializedParameters = $TemplateParameterObject | ConvertTo-Json -Depth 100 -Compress |
        ConvertFrom-Json -AsHashtable
    if ($serializedParameters.adminPassword -cne $TemplateParameterObject.adminPassword) {
        throw 'Password changed during parameter serialization.'
    }
    $global:ArcMock.deployments.Add($TemplateParameterObject)
    $global:ArcMock.vms += [pscustomobject]@{
        name = $TemplateParameterObject.virtualMachineName
        resourceGroup = $ResourceGroupName
        location = $TemplateParameterObject.location
        hardwareProfile = [pscustomobject]@{ vmSize = $TemplateParameterObject.virtualMachineSize }
        provisioningState = 'Succeeded'
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
            if ($arguments[2] -eq 'show') {
                if ((Get-MockArgument $arguments '--query') -ne 'location') {
                    throw 'Unexpected placement deployment query.'
                }
                return (ConvertTo-Json -InputObject $global:ArcMock.sharedLocation -Compress)
            }
            # Match Azure's nested projection: one deployment containing an array.
            return (ConvertTo-Json -InputObject @(
                if ($global:ArcMock.placement.Count -gt 0) { ,$global:ArcMock.placement }
            ) -Depth 30 -Compress)
        }
        'resource list' {
            if ((Get-MockArgument $arguments '--query') -ne '{resources:@}') {
                throw 'Resource inventory must preserve an explicit empty array.'
            }
            if ($global:ArcMock.inventoryShape -eq 'missing') { return '{}' }
            if ($global:ArcMock.inventoryShape -eq 'null') { return '{"resources":null}' }
            if ($global:ArcMock.inventoryShape -eq 'object') { return '{"resources":{}}' }
            @{
                resources = @(
                    $global:ArcMock.otherResources
                    foreach ($vm in $global:ArcMock.vms) {
                        @{
                            id = "/subscriptions/$subscription/resourceGroups/$($vm.resourceGroup)/providers/Microsoft.Compute/virtualMachines/$($vm.name)"
                            type = 'Microsoft.Compute/virtualMachines'
                        }
                    }
                    foreach ($ip in $global:ArcMock.partialIps) {
                        @{
                            id = "/subscriptions/$subscription/resourceGroups/$($ip.resourceGroup)/providers/Microsoft.Network/publicIPAddresses/$($ip.name)"
                            type = 'Microsoft.Network/publicIPAddresses'
                        }
                    }
                )
            }
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
            @(
                foreach ($counter in $global:ArcMock.networkUsages) {
                    if ($counter.name.value -eq 'PublicIPAddresses') {
                        $counter.currentValue = $global:ArcMock.totalNetworkUsed
                        $counter.limit = $global:ArcMock.totalNetworkQuota
                    }
                    if ($counter.name.value -eq 'IPv4StandardSkuPublicIpAddresses') {
                        if ($global:ArcMock.missingNetworkQuota) { continue }
                        $counter.currentValue = $global:ArcMock.networkUsed
                        $counter.limit = $global:ArcMock.networkQuota
                        if ($global:ArcMock.duplicateNetworkQuota) { $counter }
                    }
                    $counter
                }
            )
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
            if (-not $vm.PSObject.Properties['tags'] -or -not $vm.tags) {
                $global:LASTEXITCODE = 1
                return "ERROR: Couldn't find 'tags' in ''."
            }
            $tag = (Get-MockArgument $arguments '--set') -split '=', 2
            $vm.tags | Add-Member -NotePropertyName ($tag[0] -replace '^tags\.', '') -NotePropertyValue $tag[1] -Force
            $vm
        }
        'tag update' {
            if ((Get-MockArgument $arguments '--operation') -ne 'Merge') {
                throw 'Tag updates must merge without replacing other tags.'
            }
            $id = Get-MockArgument $arguments '--resource-id'
            $group = @($global:ArcMock.users | ForEach-Object {
                "rg-$($_.Substring($_.Length - 2))"
            } | Where-Object { $id -eq "/subscriptions/$subscription/resourceGroups/$_" })
            if ($group.Count -eq 1) {
                if ((Get-MockArgument $arguments '--tags') -cne 'SecurityControl=Ignore') {
                    throw 'RG tag update must set SecurityControl=Ignore.'
                }
                if ($global:ArcMock.invalidGroupTagResponse) { return '{"properties":{"tags":{}}}' }
                if (-not $global:ArcMock.groupTags.ContainsKey($group[0])) {
                    $global:ArcMock.groupTags[$group[0]] = [pscustomobject]@{}
                }
                $global:ArcMock.groupTags[$group[0]] | Add-Member -NotePropertyName SecurityControl -NotePropertyValue Ignore -Force
                return (ConvertTo-Json -InputObject @{ properties = @{ tags = $global:ArcMock.groupTags[$group[0]] } } -Depth 30 -Compress)
            }
            $vm = @($global:ArcMock.vms | Where-Object {
                $id -eq "/subscriptions/$subscription/resourceGroups/$($_.resourceGroup)/providers/Microsoft.Compute/virtualMachines/$($_.name)"
            })
            if ($vm.Count -ne 1) { throw 'Tag update must target exactly one VM resource ID.' }
            if (-not $vm[0].PSObject.Properties['tags'] -or -not $vm[0].tags) {
                $vm[0] | Add-Member -NotePropertyName tags -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $tag = (Get-MockArgument $arguments '--tags') -split '=', 2
            $vm[0].tags | Add-Member -NotePropertyName $tag[0] -NotePropertyValue $tag[1] -Force
            @{ properties = @{ tags = $vm[0].tags } }
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
    param([string]$Locations = ($regions -join ','), [string]$LabPath = $labRoot)
    & (Join-Path $LabPath 'shared-deploy-lab.ps1') -SubscriptionId $subscription `
        -PreferredLocation $Locations -AllowedEntraUserIds $global:ArcMock.users
}

function Invoke-Lab {
    param(
        [string]$User = $users[0],
        [string]$Group = 'rg-01',
        [string]$Type = 'resourcegroup',
        [string[]]$Locations = $regions,
        [string]$LabPath = $labRoot
    )
    & (Join-Path $LabPath 'deploy-lab.ps1') -DeploymentType $Type -SubscriptionId $subscription `
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
$source = Get-Content (Join-Path $labRoot 'demo-vm-creator\create_vms.sh') -Raw
Assert-Test (-not $source.Contains("`r")) 'Standalone Bash creator uses Unix line endings'
$setupAssets = @(
    'AddKey.zip', 'ChangeTracking\template-DCR-ChangeTracking.json',
    'cleanup\1-resource-groups.ps1', 'demo-vm-creator\.gitattributes',
    'demo-vm-creator\create_vms.ps1', 'demo-vm-creator\create_vms.sh',
    'demo-vm-creator\parameters-win2012.json', 'demo-vm-creator\README.md',
    'demo-vm-creator\template-win2012.json',
    'demo-vm-onboarder\arc-enable-vms.sh', 'demo-vm-onboarder\create-and-onboard.sh',
    'demo-vm-onboarder\onboard-linux.yml', 'demo-vm-onboarder\onboard-win.yml',
    'demo-vm-onboarder\README.md', 'subscription-preparations\1-resource-providers.ps1',
    'subscription-preparations\2-vcpu-quotas.ps1', 'subscription-preparations\3-rbac.ps1'
)
foreach ($name in $setupAssets) {
    Assert-Test (Test-Path -LiteralPath (Join-Path $labRoot $name) -PathType Leaf) "Setup asset is centralized: $name"
}
Assert-Test (-not (Test-Path -LiteralPath (Join-Path (Split-Path $labRoot -Parent) 'resources'))) 'No setup assets remain in the former resources directory'
foreach ($file in Get-ChildItem $labRoot -Filter '*.json' -Recurse) {
    $document = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable
    Assert-Test ($null -ne $document) "Central setup JSON parses: $($file.Name)"
}
$creatorPath = Join-Path $labRoot 'demo-vm-creator\create_vms.ps1'
$creatorSource = Get-Content -LiteralPath $creatorPath -Raw
Assert-Test (-not ($creatorSource -match '-TemplateUri|-SourceScriptUri|raw\.githubusercontent\.com')) 'Legacy PowerShell creator consumes local setup assets rather than remote repository URLs'
$templatePaths = @([regex]::Matches($creatorSource, '(?m)^\$TemplateFile = Join-Path \$(labautomationRoot|PSScriptRoot) ''([^'']+)''') | ForEach-Object {
    $root = if ($_.Groups[1].Value -eq 'labautomationRoot') { $labRoot } else { Split-Path $creatorPath -Parent }
    Join-Path $root $_.Groups[2].Value
})
Assert-Test ($templatePaths.Count -eq 3) 'Legacy PowerShell creator resolves three local templates'
$creatorAst = [System.Management.Automation.Language.Parser]::ParseFile($creatorPath, [ref]$null, [ref]$null)
$rgCreateCommands = @($creatorAst.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.CommandAst] -and
    $node.GetCommandName() -eq 'New-AzResourceGroup'
}, $true))
Assert-Test ($rgCreateCommands.Count -eq 1) 'Legacy creator has one RG creation surface'
Assert-Test ($rgCreateCommands[0].Extent.Text -match '-Tag @\{ SecurityControl = ''Ignore'' \}') 'Legacy creator tags new RGs at creation'
$parameterAssignments = @($creatorAst.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
    $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
    $node.Left.VariablePath.UserPath -eq 'TemplateParameters'
}, $true))
Assert-Test ($parameterAssignments.Count -eq 3) 'Legacy creator defines parameters for all three templates'
for ($i = 0; $i -lt $templatePaths.Count; $i++) {
    Assert-Test (Test-Path -LiteralPath $templatePaths[$i]) 'Legacy creator local template exists'
    $template = Get-Content -LiteralPath $templatePaths[$i] -Raw | ConvertFrom-Json -AsHashtable
    $parameterTable = $parameterAssignments[$i].Right.Find({
        param($node)
        $node -is [System.Management.Automation.Language.HashtableAst]
    }, $false)
    $keys = @($parameterTable.KeyValuePairs | ForEach-Object { $_.Item1.Value })
    foreach ($key in $keys) {
        Assert-Test ($key -in $template.parameters.Keys) "Legacy creator parameter '$key' exists in its local template"
    }
    foreach ($key in $template.parameters.Keys) {
        Assert-Test ($key -in $keys -or $template.parameters[$key].Contains('defaultValue')) "Legacy creator supplies required template parameter '$key'"
    }
}
$bashRegions = [regex]::Match($source, '(?m)^regions=\(([^)]+)\)').Groups[1].Value
$bashRegions = @([regex]::Matches($bashRegions, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
$defaultRegions = @($defaults.preferredLocation.Split(',') | ForEach-Object { $_.Trim() })
Assert-Test ($defaultRegions.Count -gt 0 -and '' -notin $defaultRegions) 'Defaults contain non-empty region names'
Assert-Test (($bashRegions -join ',') -eq ($defaultRegions -join ',')) 'Default region order matches verified Bash independently of Console test fixtures'
Assert-Test ($source -match 'virtualWinMachineSize="Standard_D4ads_v5"') 'Windows SKU matches Bash'
Assert-Test ($source -match 'virtualLnxMachineSize="Standard_D2ads_v5"') 'Linux SKU matches Bash'

Reset-Mock
Invoke-Shared
Assert-Test ($global:ArcMock.sharedTemplatePaths.Count -eq 1) 'Shared deployment receives a JSON file instead of a PowerShell TemplateObject'
Assert-Test (-not (Test-Path -LiteralPath $global:ArcMock.sharedTemplatePaths[0])) 'Temporary shared template removed after success'
Assert-Test ($global:ArcMock.sharedTemplates[0].outputs.placement.value.Count -eq 7) 'All participant strings survive JSON serialization'
Assert-Test ($global:ArcMock.placement.Count -eq 7) 'All Console participants mapped'
Assert-Test ($global:ArcMock.placement[5].location -eq $regions[0]) 'Round-robin wraps'
Assert-Test ($global:ArcMock.registrations.Count -eq 15) 'Providers registered once'
Assert-Test ($global:ArcMock.groupTags.Count -eq 7) 'Shared hook tags all Console participant RGs'
Assert-Test (@($global:ArcMock.groupTags.Values | Where-Object { $_.SecurityControl -cne 'Ignore' }).Count -eq 0) 'Every participant RG has exactly SecurityControl=Ignore'
Assert-Test (-not $global:ArcMock.registrations.ContainsKey('Microsoft.Quota')) 'No unnecessary Quota provider dependency'
Assert-Test (@($global:ArcMock.calls | Where-Object {
    $_[0] -eq 'network' -and $_[1] -eq 'list-usages'
}).Count -eq 5) 'Confirmed network usage counters read once per deployment region'
Assert-Test (@($global:ArcMock.calls | Where-Object { $_[0] -eq 'rest' }).Count -eq 0) 'No quota REST requests are needed'
Assert-Test (@($global:ArcMock.networkUsages | Where-Object {
    $_.name.value -eq 'IPv4BasicSkuPublicIpAddresses' -and $_.limit -eq '0'
}).Count -eq 1) 'Live-shaped fixture includes Basic IPv4 quota zero without blocking Standard deployment'
$global:ArcMock.users = @($global:ArcMock.users | Sort-Object -Descending)
Invoke-Shared
Assert-Test ($global:ArcMock.placement[0].userId -eq $users[0]) 'Input ordering does not affect placement'
Assert-Test ($global:ArcMock.sharedTemplatePaths[0] -ne $global:ArcMock.sharedTemplatePaths[1]) 'Shared reruns use unique temporary paths'

$credentials = @(Invoke-Lab)
Assert-Test ($global:ArcMock.deployments.Count -eq 2) 'Exactly two VMs, no Windows 2012'
Assert-Test ($global:ArcMock.deployments[0].virtualMachineSize -eq 'Standard_D2ads_v5') 'Linux size'
Assert-Test ($global:ArcMock.deployments[1].virtualMachineSize -eq 'Standard_D4ads_v5') 'Windows size'
Assert-Test ($global:ArcMock.deployments[0].networkSecurityGroupRules[0].properties.destinationPortRange -eq '22') 'Existing SSH rule'
Assert-Test ($global:ArcMock.deployments[1].networkSecurityGroupRules.Count -eq 2) 'Existing RDP/WinRM rules'
Assert-Test ($credentials.Count -eq 5) 'Only dashboard credentials on success stream'
Assert-Test ($credentials[-1].HackboxCredential.value -like '*NOT verified*') 'Honest asynchronous status'
Assert-Test ($credentials[1].HackboxCredential.value -eq 'OfflineOnlyPassword123') 'Per-lab password returned after acceptance'
Assert-Test ($global:ArcMock.deployments[0].adminPassword -ceq $credentials[1].HackboxCredential.value) 'Linux receives the dashboard password as a serializable ARM parameter value'
Assert-Test ($global:ArcMock.deployments[1].adminPassword -ceq $credentials[1].HackboxCredential.value) 'Windows receives the same serializable dashboard password'
Assert-Test (@($global:ArcMock.calls | Where-Object { $_[0] -eq 'vm' -and $_[1] -eq 'update' }).Count -eq 0) 'All VM tag writes use tag Merge instead of nested VM updates'
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
Assert-Test ($global:ArcMock.sharedTemplates[0].outputs.placement.value.Count -eq 1) 'Single-user placement remains an array in the template file'
foreach ($failure in @('throw', 'state')) {
    Reset-Mock -Count 1
    $global:ArcMock.sharedFailure = $failure
    $expected = if ($failure -eq 'throw') { 'Mock shared deployment failed' } else { 'Saving participant placement failed: Failed' }
    Assert-Throws { Invoke-Shared } $expected
    Assert-Test ($global:ArcMock.sharedTemplatePaths.Count -eq 1) 'Failure occurs after reading the generated template'
    Assert-Test (-not (Test-Path -LiteralPath $global:ArcMock.sharedTemplatePaths[0])) 'Temporary template removed after a shared deployment failure'
    Assert-Test ($global:ArcMock.placement.Count -eq 0) 'Failed shared deployment does not publish participant placement'
}
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
Assert-Test ($global:ArcMock.placement.Count -eq 0) 'Insufficient Standard IP quota cannot publish placement'
Reset-Mock -Count 1
$global:ArcMock.networkQuota = 2
Invoke-Shared
Assert-Test ($global:ArcMock.placement.Count -eq 1) 'Exact IPv4 Standard quota threshold passes with real counter names'
Reset-Mock -Count 1
$global:ArcMock.networkQuota = 2
$global:ArcMock.networkUsed = 1
Assert-Throws { Invoke-Shared } 'Insufficient quota'
foreach ($invalid in @($null, 'not-a-number', -1)) {
    Reset-Mock -Count 1
    $global:ArcMock.networkQuota = $invalid
    Assert-Throws { Invoke-Shared } 'missing or invalid limit/usage data'
    Assert-Test ($global:ArcMock.placement.Count -eq 0) 'Invalid Standard IP limit cannot publish placement'
    Reset-Mock -Count 1
    $global:ArcMock.networkUsed = $invalid
    Assert-Throws { Invoke-Shared } 'missing or invalid limit/usage data'
}
Reset-Mock -Count 1
$global:ArcMock.missingNetworkQuota = $true
Assert-Throws { Invoke-Shared } "Cannot verify quota 'IPv4StandardSkuPublicIpAddresses'"
Reset-Mock -Count 1
$global:ArcMock.duplicateNetworkQuota = $true
Assert-Throws { Invoke-Shared } "Cannot verify quota 'IPv4StandardSkuPublicIpAddresses'"
Reset-Mock -Count 1
$global:ArcMock.totalNetworkQuota = 1
Assert-Throws { Invoke-Shared } "Insufficient quota 'PublicIPAddresses'"
Reset-Mock -Count 1
$global:ArcMock.totalNetworkQuota = 2
$global:ArcMock.totalNetworkUsed = 1
Assert-Throws { Invoke-Shared } "Insufficient quota 'PublicIPAddresses'"
Reset-Mock -Count 1
$ipv6 = $global:ArcMock.networkUsages | Where-Object { $_.name.value -eq 'IPv6StandardSkuPublicIpAddresses' }
$ipv6.limit = '0'
Invoke-Shared
Assert-Test ($global:ArcMock.placement.Count -eq 1) 'IPv6 Standard limit does not constrain IPv4 VMs'
Reset-Mock -Count 1
$global:ArcMock.failCommand = 'network list-usages'
Assert-Throws { Invoke-Shared } 'Azure CLI failed (network list-usages)'
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
$global:ArcMock.failCommand = 'microhackArcUserId='
Assert-Throws { Invoke-Lab } 'Azure CLI failed'
Assert-Test ($global:ArcMock.vms.Count -eq 1) 'Tag API failure leaves the newly created VM for recovery'
Assert-Test (@($global:ArcMock.calls | Where-Object { $_[0] -eq 'vm' -and $_[1] -eq 'run-command' }).Count -eq 0) 'Failed ownership tagging never submits reconfiguration'
$global:ArcMock.failCommand = ''
Invoke-Shared
Invoke-Lab | Out-Null
Assert-Test ($global:ArcMock.deployments.Count -eq 2) 'Retry after ownership-tag failure reuses Linux and only creates the missing Windows VM'
Assert-Test ($global:ArcMock.vms[0].tags.microhackArcUserId -eq $users[0]) 'Retry restores the missing ownership tag'

Reset-Mock -Count 1
$global:ArcMock.groupTags['rg-01'] = [pscustomobject]@{ keep = 'unchanged'; SecurityControl = 'Enforce' }
Invoke-Shared
Assert-Test ($global:ArcMock.groupTags['rg-01'].SecurityControl -ceq 'Ignore') 'Shared stage replaces a conflicting SecurityControl value with Ignore'
Assert-Test ($global:ArcMock.groupTags['rg-01'].keep -ceq 'unchanged') 'Shared RG tagging preserves unrelated tags'
$global:ArcMock.groupTags['rg-01'].SecurityControl = 'Enforce'
Invoke-Lab | Out-Null
Assert-Test ($global:ArcMock.groupTags['rg-01'].SecurityControl -ceq 'Ignore') 'Participant stage restores RG tag before VM deployment even after shared stage'
Assert-Test ($global:ArcMock.groupTags['rg-01'].keep -ceq 'unchanged') 'Participant RG tagging preserves unrelated tags'
Assert-Test (@($global:ArcMock.groupTags.Keys | Where-Object { $_ -ne 'rg-01' }).Count -eq 0) 'RG tagging only targets participant RGs, never governance or unrelated groups'

Reset-Mock -Count 1
$global:ArcMock.failCommand = 'tag update'
Assert-Throws { Invoke-Shared } 'Azure CLI failed'
Assert-Test ($global:ArcMock.sharedTemplatePaths.Count -eq 0) 'Shared tagging failure does not publish successful placement'
Assert-Test ($global:ArcMock.deployments.Count -eq 0) 'Shared tagging failure cannot deploy VMs'
Reset-Mock -Count 1
Invoke-Shared
$global:ArcMock.failCommand = 'tag update'
Assert-Throws { Invoke-Lab } 'Azure CLI failed'
Assert-Test ($global:ArcMock.vms.Count -eq 0) 'Participant RG tagging failure aborts before any VM creation'
foreach ($stage in @('shared', 'participant')) {
    Reset-Mock -Count 1
    if ($stage -eq 'participant') { Invoke-Shared }
    $global:ArcMock.invalidGroupTagResponse = $true
    if ($stage -eq 'shared') {
        Assert-Throws { Invoke-Shared } 'did not confirm SecurityControl=Ignore'
    } else {
        Assert-Throws { Invoke-Lab } 'did not confirm SecurityControl=Ignore'
    }
    Assert-Test ($global:ArcMock.vms.Count -eq 0) 'Missing RG tag confirmation aborts instead of assuming the tag was applied'
}

foreach ($tagShape in @('missing', 'null', 'empty', 'custom', 'empty-owner', 'submitted')) {
    Reset-Mock -Count 1
    Invoke-Shared
    $vm = [pscustomobject]@{
        name = 'vm-linux-mh'
        resourceGroup = 'rg-01'
        location = 'swedencentral'
        hardwareProfile = [pscustomobject]@{ vmSize = 'Standard_D2ads_v5' }
        provisioningState = 'Succeeded'
    }
    if ($tagShape -ne 'missing') {
        $tags = switch ($tagShape) {
            'null' { $null }
            'empty' { [pscustomobject]@{} }
            'custom' { [pscustomobject]@{ keep = 'unchanged' } }
            'empty-owner' { [pscustomobject]@{ microhackArcUserId = '' } }
            'submitted' { [pscustomobject]@{ microhackReconfiguration = 'submitted' } }
        }
        $vm | Add-Member -NotePropertyName tags -NotePropertyValue $tags
    }
    $global:ArcMock.vms = @($vm)
    Invoke-Shared
    Assert-Test (@($global:ArcMock.calls | Where-Object { $_[0] -eq 'tag' -and (Get-MockArgument $_ '--resource-id') -match '/providers/Microsoft.Compute/virtualMachines/' }).Count -eq 0) 'Shared preflight allows unmarked expected VMs without changing VM tags'
    $recovered = @(Invoke-Lab)
    Assert-Test ($global:ArcMock.deployments.Count -eq 1) 'Existing unmarked Linux VM is reused rather than redeployed'
    Assert-Test ($global:ArcMock.vms[0].tags.microhackArcUserId -eq $users[0]) "Ownership tag is initialized for $tagShape tags"
    Assert-Test ($global:ArcMock.vms[0].tags.microhackReconfiguration -eq 'submitted') 'Reconfiguration state is merged into initialized VM tags'
    Assert-Test ($recovered.Count -eq 5) 'Recovery completes both VMs and dashboard output'
    if ($tagShape -eq 'custom') {
        Assert-Test ($global:ArcMock.vms[0].tags.keep -eq 'unchanged') 'Ownership and state tag updates preserve unrelated VM tags'
    }
    if ($tagShape -eq 'submitted') {
        Assert-Test (@($global:ArcMock.calls | Where-Object {
            $_[0] -eq 'vm' -and $_[1] -eq 'run-command' -and $_[2] -eq 'invoke'
        }).Count -eq 0) 'Adding a missing owner tag preserves submitted state without contacting the stopped Linux agent'
    }
}

Reset-Mock -Count 1
Invoke-Shared
$global:ArcMock.vms = @(
    foreach ($type in @('linux', 'win2025')) {
        [pscustomobject]@{
            name = "vm-$type-mh"
            resourceGroup = 'rg-01'
            location = 'swedencentral'
            hardwareProfile = [pscustomobject]@{ vmSize = if ($type -eq 'linux') { 'Standard_D2ads_v5' } else { 'Standard_D4ads_v5' } }
            provisioningState = 'Succeeded'
        }
    }
)
Invoke-Shared
Invoke-Lab | Out-Null
Assert-Test ($global:ArcMock.deployments.Count -eq 0) 'Both existing unmarked VM types are reused without ARM redeployment'
Assert-Test (@($global:ArcMock.vms | Where-Object { $_.tags.microhackArcUserId -eq $users[0] }).Count -eq 2) 'Recovery tags both Linux and Windows with the current participant ID'

Reset-Mock -Count 1
Invoke-Shared
$global:ArcMock.vms = @([pscustomobject]@{
    name = 'vm-not-a-lab'
    resourceGroup = 'rg-01'
    location = 'swedencentral'
    hardwareProfile = [pscustomobject]@{ vmSize = 'Standard_D2ads_v5' }
    provisioningState = 'Succeeded'
})
Invoke-Shared
Invoke-Lab | Out-Null
Assert-Test (-not $global:ArcMock.vms[0].PSObject.Properties['tags']) 'Unmarked VMs without an expected lab name remain untouched'
Assert-Test ($global:ArcMock.deployments.Count -eq 2) 'An unrelated VM is not substituted for either expected lab VM'

foreach ($conflict in @('owner', 'location', 'size', 'state')) {
    Reset-Mock -Count 1
    Invoke-Shared
    $vm = [pscustomobject]@{
        name = 'vm-linux-mh'
        resourceGroup = 'rg-01'
        location = 'swedencentral'
        hardwareProfile = [pscustomobject]@{ vmSize = 'Standard_D2ads_v5' }
        provisioningState = 'Succeeded'
        tags = [pscustomobject]@{ keep = 'unchanged' }
    }
    $pattern = switch ($conflict) {
        'owner' {
            $vm.tags | Add-Member -NotePropertyName microhackArcUserId -NotePropertyValue $users[1]
            'not marked as belonging'
        }
        'location' { $vm.location = 'westus2'; 'No VM will be moved' }
        'size' { $vm.hardwareProfile.vmSize = 'Standard_D4ads_v5'; 'No VM will be moved' }
        'state' { $vm.provisioningState = 'Failed'; 'not successfully provisioned' }
    }
    $global:ArcMock.vms = @($vm)
    $sharedPattern = if ($conflict -eq 'location') { 'does not match its assigned region' } else { $pattern }
    Assert-Throws { Invoke-Shared } $sharedPattern
    Assert-Throws { Invoke-Lab } $pattern
    Assert-Test (@($global:ArcMock.calls | Where-Object { $_[0] -eq 'tag' -and (Get-MockArgument $_ '--resource-id') -match '/providers/Microsoft.Compute/virtualMachines/' }).Count -eq 0) 'Conflicting VMs are not retagged by either deployment stage'
    Assert-Test ($global:ArcMock.deployments.Count -eq 0) 'Conflicting VMs are not redeployed'
}

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
Invoke-Shared
Assert-Test ($global:ArcMock.placement.Count -eq 1 -and $global:ArcMock.placement[0].userId -eq $users[1]) 'Stale placement can be replaced when the subscription is empty'
Assert-Test ($global:ArcMock.placement[0].location -eq 'swedencentral') 'Remaining participant is remapped according to the current Console list'
Assert-Test ($global:ArcMock.sharedLocation -eq 'swedencentral') 'Metadata location remains unchanged after participant replanning'

Reset-Mock -Count 2
Invoke-Shared -Locations 'swedencentral,australiaeast'
Invoke-Shared -Locations 'westus2,swedencentral'
Assert-Test (($global:ArcMock.placement.location -join ',') -eq 'westus2,swedencentral') 'Empty subscription accepts a new ordered region list'
Assert-Test ($global:ArcMock.sharedLocation -eq 'swedencentral') 'New first VM region does not relocate the existing deployment record'
Invoke-Lab -Locations @('westus2', 'swedencentral') | Out-Null
Assert-Test ($global:ArcMock.deployments[0].location -eq 'westus2') 'VMs use the new region, not the retained metadata location'
Assert-Throws { Invoke-Shared -Locations 'australiaeast,swedencentral' } 'remove or relocate'
Assert-Test (($global:ArcMock.placement.location -join ',') -eq 'westus2,swedencentral') 'VM presence protects the prior mapping from replacement'

foreach ($resourceType in @('Microsoft.Network/networkInterfaces', 'Microsoft.Compute/disks', 'Microsoft.Storage/storageAccounts')) {
    Reset-Mock -Count 2
    Invoke-Shared
    $global:ArcMock.otherResources = @(@{
        id = "/subscriptions/$subscription/resourceGroups/rg-01/providers/$resourceType/existing"
        type = $resourceType
    })
    $global:ArcMock.users = @($users[1])
    Assert-Throws { Invoke-Shared } 'remove or relocate'
    Assert-Test ($global:ArcMock.placement.Count -eq 2) 'Any existing resource prevents stale placement replacement'
    Assert-Test ($global:ArcMock.sharedTemplatePaths.Count -eq 1) 'Blocked replan does not overwrite the deployment record'
}
Reset-Mock -Count 2
Invoke-Shared
$global:ArcMock.partialIps = @(@{ name = 'vm-linux-mh-pip'; resourceGroup = 'rg-01'; location = 'swedencentral' })
$global:ArcMock.users = @($users[1])
Assert-Throws { Invoke-Shared } 'remove or relocate'

Reset-Mock -Count 2
Invoke-Shared
$global:ArcMock.otherResources = @(
    @{ id = "/subscriptions/$subscription/resourceGroups/rg-01"; type = 'Microsoft.Resources/resourceGroups' },
    @{ id = "/subscriptions/$subscription/providers/Microsoft.Resources/deployments/old"; type = 'Microsoft.Resources/deployments' }
)
$global:ArcMock.users = @($users[1])
Invoke-Shared
Assert-Test ($global:ArcMock.placement.Count -eq 1) 'Only RGs and deployment metadata do not block empty-subscription replanning'

$approvedWorkspaceId = '/subscriptions/06dd34f3-80d4-42a0-ac31-446add752cd8/resourceGroups/McapsGovernance/providers/Microsoft.OperationalInsights/workspaces/mcaps42a0ac31446add752cd8-la'
Reset-Mock -Count 2
Invoke-Shared
$global:ArcMock.otherResources = @(@{
    id = $approvedWorkspaceId.ToUpperInvariant()
    type = 'Microsoft.OperationalInsights/workspaces'
})
$global:ArcMock.users = @($users[1])
Invoke-Shared
Assert-Test ($global:ArcMock.placement.Count -eq 1) 'The explicitly approved workspace permits replanning with case-insensitive ARM identity matching'
Assert-Test ($global:ArcMock.otherResources.Count -eq 1 -and $global:ArcMock.otherResources[0].id -ceq $approvedWorkspaceId.ToUpperInvariant()) 'The approved workspace remains untouched'

foreach ($resource in @(
    @{ id = "$approvedWorkspaceId-other"; type = 'Microsoft.OperationalInsights/workspaces' },
    @{ id = $approvedWorkspaceId.Replace('/McapsGovernance/', '/other-group/'); type = 'Microsoft.OperationalInsights/workspaces' },
    @{ id = $approvedWorkspaceId.Replace('06dd34f3-80d4-42a0-ac31-446add752cd8', $subscription); type = 'Microsoft.OperationalInsights/workspaces' },
    @{ id = '/subscriptions/06dd34f3-80d4-42a0-ac31-446add752cd8/resourceGroups/McapsGovernance/providers/Microsoft.Storage/storageAccounts/other'; type = 'Microsoft.Storage/storageAccounts' },
    @{ id = $approvedWorkspaceId; type = 'Microsoft.Storage/storageAccounts' }
)) {
    Reset-Mock -Count 2
    Invoke-Shared
    $global:ArcMock.otherResources = @(
        @{ id = $approvedWorkspaceId; type = 'Microsoft.OperationalInsights/workspaces' },
        $resource
    )
    $global:ArcMock.users = @($users[1])
    Assert-Throws { Invoke-Shared } 'contains 1 resource(s)'
    Assert-Test ($global:ArcMock.placement.Count -eq 2) 'The workspace exemption cannot allow a different resource to authorize replanning'
    Assert-Test ($global:ArcMock.sharedTemplatePaths.Count -eq 1) 'A blocked replan preserves the existing metadata alongside the exempt workspace'
}

foreach ($shape in @('missing', 'null', 'object')) {
    Reset-Mock -Count 2
    Invoke-Shared
    $global:ArcMock.users = @($users[1])
    $global:ArcMock.inventoryShape = $shape
    Assert-Throws { Invoke-Shared } 'invalid resource inventory'
    Assert-Test ($global:ArcMock.placement.Count -eq 2) 'Malformed inventory cannot authorize placement replacement'
}
Reset-Mock -Count 2
Invoke-Shared
$global:ArcMock.users = @($users[1])
$global:ArcMock.failCommand = 'resource list'
Assert-Throws { Invoke-Shared } 'Azure CLI failed'
Assert-Test ($global:ArcMock.placement.Count -eq 2) 'Inventory API failure preserves the previous mapping'
Reset-Mock -Count 1
Invoke-Shared
$global:ArcMock.sharedLocation = ''
Assert-Throws { Invoke-Shared } 'Cannot read the existing placement deployment location'
Assert-Test ($global:ArcMock.sharedTemplatePaths.Count -eq 1) 'Missing deployment location cannot overwrite existing metadata'
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

$assetNames = @(
    'parameters-linux.json', 'parameters-win2025.json',
    'template-linux.json', 'template-win2025.json',
    'reconfig-ubuntu.sh', 'reconfig-win.ps1'
)
$packageRoot = Join-Path ([System.IO.Path]::GetTempPath()) "microhack-arc-package-$([guid]::NewGuid().ToString('N'))"
try {
    New-Item -ItemType Directory -Path $packageRoot | Out-Null
    foreach ($name in @('common.ps1', 'deploy-lab.ps1', 'shared-deploy-lab.ps1', 'lab-defaults.json') + $assetNames) {
        Copy-Item -LiteralPath (Join-Path $labRoot $name) -Destination (Join-Path $packageRoot $name)
    }
    Reset-Mock -Count 1
    Invoke-Shared -LabPath $packageRoot
    $credentials = @(Invoke-Lab -LabPath $packageRoot)
    Assert-Test ($global:ArcMock.deployments.Count -eq 2) 'Standalone labautomation package deploys both VMs without the repository layout'
    Assert-Test ($credentials.Count -eq 5) 'Standalone package emits all dashboard credentials'
    foreach ($path in $global:ArcMock.vmTemplatePaths) {
        Assert-Test ((Split-Path $path -Parent) -eq $packageRoot) 'VM deployment uses a template inside the imported package'
    }
    $runCommands = @($global:ArcMock.calls | Where-Object { $_[0] -eq 'vm' -and $_[1] -eq 'run-command' })
    Assert-Test ($runCommands.Count -eq 2) 'Standalone package submits both reconfiguration requests'
    foreach ($command in $runCommands) {
        $option = if ($command[2] -eq 'invoke') { '--scripts' } else { '--script' }
        $path = (Get-MockArgument $command $option).Substring(1)
        Assert-Test ((Split-Path $path -Parent) -eq $packageRoot) 'Reconfiguration uses a script inside the imported package'
    }
    foreach ($name in $assetNames) {
        $path = Join-Path $packageRoot $name
        Remove-Item -LiteralPath $path -Force
        Reset-Mock -Count 1
        Assert-Throws { Invoke-Shared -LabPath $packageRoot } "Missing required files: $name"
        Assert-Throws { Invoke-Lab -LabPath $packageRoot } "Missing required files: $name"
        Assert-Test ($global:ArcMock.calls.Count -eq 0) "Missing $name fails before any Azure CLI call"
        Assert-Test ($global:ArcMock.deployments.Count -eq 0) "Missing $name fails before VM deployment"
        Copy-Item -LiteralPath (Join-Path $labRoot $name) -Destination $path
    }
} finally {
    if (Test-Path -LiteralPath $packageRoot) {
        Remove-Item -LiteralPath $packageRoot -Recurse -Force -ErrorAction Stop
    }
}

Write-Host "PASS: $script:Assertions offline assertions. No Azure login or network calls were made."
