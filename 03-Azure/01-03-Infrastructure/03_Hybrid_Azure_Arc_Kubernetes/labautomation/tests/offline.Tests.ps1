$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'common.ps1')
$checks = 0

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
    $script:checks++
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Pattern)
    $message = ''
    try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
    Assert-Test ($message -like "*$Pattern*") "Expected failure containing '$Pattern'; got '$message'."
}

Get-ChildItem $root -Filter '*.ps1' -Recurse | ForEach-Object {
    $tokens = $null
    $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    Assert-Test ($errors.Count -eq 0) "PowerShell parse error in $($_.Name): $errors"
}
$defaults = Get-Content (Join-Path $root 'lab-defaults.json') -Raw | ConvertFrom-Json
Assert-Test ($defaults.deploymentType -eq 'resourcegroup-with-subscriptionowner') 'Unexpected Console scope.'
Assert-Test ($defaults.labsPerSubscription -eq 4) 'Unexpected default participant density.'
$regions = @(Get-K8sRegions @(' GermanyWestCentral, swedencentral ', 'germanywestcentral'))
Assert-Test (($regions -join ',') -eq 'germanywestcentral,swedencentral') 'Regions must be normalized and deduplicated.'
Assert-Throws { Get-K8sRegions @(' ') } 'At least one'
Assert-Throws { Get-K8sAsset 'missing.sh' } 'missing'

$archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $root 'lab-assets.zip'))
try {
    Assert-Test ($archive.Entries.Count -eq 6) 'Expected exactly six packaged fallback assets.'
    foreach ($entry in $archive.Entries) {
        $stream = $entry.Open()
        $memory = [IO.MemoryStream]::new()
        try {
            $stream.CopyTo($memory)
            $source = Join-Path (Join-Path (Split-Path $root -Parent) 'lab') $entry.FullName
            Assert-Test ([Convert]::ToBase64String($memory.ToArray()) -eq
                [Convert]::ToBase64String([IO.File]::ReadAllBytes($source))) "Packaged asset differs from fallback: $($entry.FullName)"
        } finally {
            $stream.Dispose()
            $memory.Dispose()
        }
    }
} finally {
    $archive.Dispose()
}
foreach ($role in @('master', 'worker')) {
    $bootstrap = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(
        (Get-K8sBootstrap -Role $role -ClusterToken 'testtoken123' -MasterIp '10.1.1.10')
    ))
    Assert-Test ($bootstrap -notmatch '\$\{(admin_user|k3s_version|cluster_token|master_ip)\}|\$\$\{') 'Unrendered Terraform template.'
    Assert-Test ($bootstrap.Contains('timeout 1800 bash')) 'Bootstrap must have a deadline.'
    Assert-Test ($bootstrap.Contains('gpg --batch --yes')) 'GPG must support non-interactive retries.'
}
Assert-Throws { Get-K8sBootstrap -Role master -ClusterToken "bad'token" } 'alphanumeric'
$workstationScript = Get-K8sWorkstationScript
Assert-Test ($workstationScript -notmatch '__[A-Z_]+__') 'Unrendered workstation asset placeholder.'
Assert-Test ($workstationScript.Contains('unset MICROHACK_CONFIG')) 'Protected configuration must be removed from the child process environment.'

$script:subscription = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
$script:user1 = '11111111-1111-1111-1111-111111111111'
$script:user2 = '22222222-2222-2222-2222-222222222222'
$global:K8sTestState = @{ Groups = @{}; Calls = @(); PeeringFailure = $false; GuestFailure = $false; GuestParameters = $null }

function Get-AzContext { return @{ Subscription = @{ Id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' } } }
function Update-MhhToken {}
function Register-AzResourceProvider { param($ProviderNamespace, $ErrorAction) }
function Get-AzResourceProvider { param($ProviderNamespace, $ErrorAction) return @{ RegistrationState = 'Registered' } }
function Get-AzResourceGroup {
    param($Name, $ErrorAction)
    if (-not $Name) { return $global:K8sTestState.Groups.Values }
    return $global:K8sTestState.Groups[$Name]
}
function Remove-MhhResourceGroup {
    param($ResourceGroupName)
    $global:K8sTestState.Groups.Remove($ResourceGroupName)
    return @{ ManifestCaptured = $true; Errors = @(); SoftDeletedResidual = @() }
}
function Get-MhhStableHash {
    param([string[]]$Value, [int]$Length)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
        [Text.Encoding]::UTF8.GetBytes(($Value -join '|'))
    )).ToLowerInvariant().Substring(0, $Length)
}
function New-MhhStablePassword { param($Purpose) return "Test-Password1!$Purpose" }
function Invoke-MhhSynchronized { param($Name, $ScriptBlock) & $ScriptBlock }
function New-AzResourceGroupDeployment {
    param($ResourceGroupName, $Name, $TemplateFile, $TemplateParameterObject, $ErrorAction)
    if ((Split-Path $TemplateFile -Leaf) -eq 'workstation-setup.bicep') {
        $global:K8sTestState.GuestParameters = $TemplateParameterObject
        if ($global:K8sTestState.GuestFailure) { throw 'Simulated guest provisioning failure' }
    } elseif ($global:K8sTestState.PeeringFailure) {
        throw 'Simulated peering failure'
    }
    return @{ ProvisioningState = 'Succeeded' }
}
function Invoke-MhhDeploymentWithRegionFallback {
    param($PreferredLocations, $ResourceGroupName, $RgOwnerEntraObjectIds, $TemplateFile, $TemplateParameterObject, $Tag)
    $global:K8sTestState.Calls += @{ Group = $ResourceGroupName; Owners = $RgOwnerEntraObjectIds; Parameters = $TemplateParameterObject; Template = (Split-Path $TemplateFile -Leaf) }
    $global:K8sTestState.Groups[$ResourceGroupName] = @{ ResourceGroupName = $ResourceGroupName; Tags = $Tag.Clone() }
    $outputs = switch (Split-Path $TemplateFile -Leaf) {
        'shared.bicep' { @{ bastionName = 'mh-k8s-bastion' } }
        'exercise.bicep' { @{ acrName = $TemplateParameterObject.acrName; workspaceName = "$($TemplateParameterObject.labPrefix)-law" } }
        'main.bicep' { @{ spokeVnetId = 'test-spoke'; workstationId = 'test-workstation' } }
    }
    return @{ Success = $true; LocationUsed = $PreferredLocations[0]; Outputs = $outputs }
}

$sharedParameters = @{
    SubscriptionId = $script:subscription
    PreferredLocation = @('germanywestcentral')
    AllowedEntraUserIds = @($script:user2, $script:user1)
}
& (Join-Path $root 'shared-deploy-lab.ps1') @sharedParameters | Out-Null
$firstAssignments = $global:K8sTestState.Groups['mh-k8s-shared'].Tags.Clone()
Assert-Test ($firstAssignments["k8s-user-$script:user1"] -eq '1') 'First network assignment missing.'
Assert-Test ($firstAssignments["k8s-user-$script:user2"] -eq '2') 'Second network assignment missing.'
$sharedParameters.AllowedEntraUserIds = @('00000000-0000-0000-0000-000000000001', $script:user1, $script:user2)
& (Join-Path $root 'shared-deploy-lab.ps1') @sharedParameters | Out-Null
Assert-Test ($global:K8sTestState.Groups['mh-k8s-shared'].Tags["k8s-user-$script:user1"] -eq '1') 'Adding a participant changed an existing address.'
Assert-Test ($global:K8sTestState.Groups['mh-k8s-shared'].Tags['k8s-user-00000000-0000-0000-0000-000000000001'] -eq '3') 'New participant must receive an unused network.'
$global:K8sTestState.Groups['mh-k8s-shared'].Tags["k8s-user-$script:user2"] = '1'
Assert-Throws { & (Join-Path $root 'shared-deploy-lab.ps1') @sharedParameters } 'duplicate'
$global:K8sTestState.Groups['mh-k8s-shared'].Tags = $firstAssignments

# Override only the external CLI boundary; exercise the real participant hook.
function global:az {
    if ($args -contains 'show') { '{"peeringState":"Connected"}' } else { '[]' }
    $global:LASTEXITCODE = 0
}
try {
    $prefixes = @()
    foreach ($user in @($script:user1, $script:user2)) {
        $global:K8sTestState.Calls = @()
        $parameters = @{
            DeploymentType = $defaults.deploymentType
            SubscriptionId = $script:subscription
            ResourceGroupName = "exercise-$($user.Substring(0, 8))"
            PreferredLocation = @('germanywestcentral')
            AllowedEntraUserIds = @($user)
        }
        $credentials = @(& (Join-Path $root 'deploy-lab.ps1') @parameters)
        $calls = $global:K8sTestState.Calls
        Assert-Test ($calls.Count -eq 2) 'Expected separate exercise and on-prem deployments.'
        Assert-Test ($calls[0].Group -eq $parameters.ResourceGroupName) 'Exercises must use the Console group.'
        Assert-Test ($calls[1].Group -ne $parameters.ResourceGroupName) 'VMs must use a separate group.'
        Assert-Test ($calls[1].Owners -contains $user) 'The extra group must grant participant Owner.'
        $configuration = $global:K8sTestState.GuestParameters.configuration
        Assert-Test ($configuration.resource_group -eq $parameters.ResourceGroupName) 'Wrong exercise context.'
        Assert-Test ($configuration.onprem_resource_group -eq $calls[1].Group) 'Wrong on-prem context.'
        Assert-Test ($credentials.Count -eq 9) "Expected nine participant dashboard credentials; got $($credentials.Count)."
        Assert-Test (@($credentials | Where-Object { $_ -isnot [hashtable] -or -not $_.HackboxCredential.value }).Count -eq 0) 'Invalid dashboard output shape.'
        $prefixes += $calls[1].Parameters.labPrefix
        $global:K8sTestState.PeeringFailure = $true
        Assert-Throws { & (Join-Path $root 'deploy-lab.ps1') @parameters } 'Simulated peering failure'
        $global:K8sTestState.PeeringFailure = $false
        $global:K8sTestState.GuestFailure = $true
        Assert-Throws { & (Join-Path $root 'deploy-lab.ps1') @parameters } 'Simulated guest provisioning failure'
        $global:K8sTestState.GuestFailure = $false
    }
    Assert-Test ($prefixes[0] -ne $prefixes[1]) 'Participant resource names must be distinct.'
    $parameters.DeploymentType = 'subscription'
    Assert-Throws { & (Join-Path $root 'deploy-lab.ps1') @parameters } 'requires a resource group'
} finally {
    Remove-Item Function:\az
}

$global:K8sTestState.Groups['unrelated'] = @{ ResourceGroupName = 'unrelated'; Tags = $null }
Assert-Throws {
    & (Join-Path $root 'cleanup.ps1') -SubscriptionId $script:subscription -ExerciseResourceGroupNames unrelated -Confirm:$false
} 'not a marked'
Assert-Throws {
    & (Join-Path $root 'cleanup.ps1') -SubscriptionId $script:subscription -RemoveSharedResources -Confirm:$false
} 'Participant resource groups remain'
$exerciseGroups = @('exercise-11111111', 'exercise-22222222')
$beforeCleanup = $global:K8sTestState.Groups.Count
& (Join-Path $root 'cleanup.ps1') -SubscriptionId $script:subscription -ExerciseResourceGroupNames $exerciseGroups -WhatIf
Assert-Test ($global:K8sTestState.Groups.Count -eq $beforeCleanup) 'Cleanup WhatIf must preserve every group.'
& (Join-Path $root 'cleanup.ps1') -SubscriptionId $script:subscription -ExerciseResourceGroupNames $exerciseGroups -RemoveSharedResources -Confirm:$false
Assert-Test ($global:K8sTestState.Groups.Count -eq 1 -and $global:K8sTestState.Groups.ContainsKey('unrelated')) 'Cleanup must remove both participant groups and shared resources, but preserve unrelated groups.'

$temporary = Join-Path ([IO.Path]::GetTempPath()) ("microhack-k8s-tests-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    foreach ($file in Get-ChildItem $root -Filter '*.bicep') {
        & az bicep build --file $file.FullName --outfile (Join-Path $temporary "$($file.BaseName).json")
        Assert-Test ($LASTEXITCODE -eq 0) "Bicep compilation failed: $($file.Name)"
    }
    $template = Get-Content (Join-Path $temporary 'main.json') -Raw | ConvertFrom-Json
    Assert-Test ($template.parameters.adminPassword.type -eq 'secureString') 'VM password must be a secure parameter.'
    $guestTemplate = Get-Content (Join-Path $temporary 'workstation-setup.json') -Raw | ConvertFrom-Json
    Assert-Test ($guestTemplate.parameters.configuration.type -eq 'secureObject') 'Guest configuration must be a secure object.'
    $runCommand = @($guestTemplate.resources | Where-Object { $_.type -eq 'Microsoft.Compute/virtualMachines/runCommands' })
    Assert-Test ($runCommand.Count -eq 1 -and $runCommand[0].properties.treatFailureAsDeploymentFailure) 'Guest failures must fail ARM deployment.'
    Assert-Test (@($template.resources | Where-Object { $_.type -match 'registries|workspaces' }).Count -eq 0) 'On-prem template must not create exercise resources.'
    $azPath = (Get-Command az).Source
    $python = Join-Path (Split-Path (Split-Path $azPath -Parent) -Parent) 'python.exe'
    if (-not (Test-Path -LiteralPath $python)) { $python = (Get-Command python3 -ErrorAction Stop).Source }
    & $python (Join-Path $PSScriptRoot 'verify-artifacts.py') $root
    Assert-Test ($LASTEXITCODE -eq 0) 'Artifact validation failed.'
} finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
Write-Host "Passed $checks offline checks. No Azure resources were deployed."
Remove-Variable K8sTestState -Scope Global
