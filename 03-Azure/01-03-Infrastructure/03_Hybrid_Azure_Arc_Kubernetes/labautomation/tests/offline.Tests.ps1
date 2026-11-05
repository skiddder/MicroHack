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
    param([scriptblock]$Action, [string]$Pattern, [string]$ForbiddenText)
    $message = ''
    $emitted = [Collections.Generic.List[object]]::new()
    try { & $Action | ForEach-Object { $emitted.Add($_) } } catch { $message = $_.Exception.Message }
    Assert-Test ($message -like "*$Pattern*") "Expected failure containing '$Pattern'; got '$message'."
    Assert-Test (@($emitted | Where-Object { $_ -is [hashtable] -and $_.ContainsKey('HackboxCredential') }).Count -eq 0) 'A failed deployment must not publish credentials.'
    if ($ForbiddenText) { Assert-Test (-not $message.Contains($ForbiddenText)) 'Guest diagnostics must redact the password.' }
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
$wslAsset = [regex]::Match($workstationScript, 'printf ''%s'' ''([^'']+)'' \| base64 -d > "\$work/scripts/setup-wsl-tools\.sh"')
Assert-Test ($wslAsset.Success) 'Rendered WSL setup asset is missing.'
$wslTools = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($wslAsset.Groups[1].Value))
Assert-Test ($wslTools.Contains('KUBECTL_VERSION=v1.33.6') -and -not $wslTools.Contains('/release/stable.txt')) 'WSL kubectl must match the pinned K3s version.'

$script:subscription = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
$script:user1 = '11111111-1111-1111-1111-111111111111'
$script:user2 = '22222222-2222-2222-2222-222222222222'
$global:K8sTestState = @{
    Subscription = $script:subscription
    Groups = @{}; Calls = @(); PeeringFailure = $false; GuestFailure = $false; GuestParameters = $null
    Deployments = @{}; PutCount = 0; ReadFailures = @(); StateSteps = @(); SubmissionFailure = $false
    DropSubmission = $false; SleepCalls = @(); ExitCodeOverride = $null; GuestRevisionOverride = $null; ExistingVms = @()
    GuestAttemptOverride = $null; GuestStateOverride = $null; UsedStandaloneCompiler = $false
    ExistingExerciseResources = @()
}

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
    param([string[]]$Value, [ValidateRange(12, [int]::MaxValue)][int]$Length)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
        [Text.Encoding]::UTF8.GetBytes(($Value -join '|'))
    )).ToLowerInvariant().Substring(0, $Length)
}
Assert-Throws { Get-MhhStableHash -Value 'test' -Length 8 } 'Length'
function New-MhhStablePassword { param($Purpose) return "Test-Password1!$Purpose" }
function Invoke-MhhSynchronized { param($Name, $ScriptBlock) & $ScriptBlock }
function New-AzResourceGroupDeployment {
    param($ResourceGroupName, $Name, $TemplateFile, $TemplateParameterObject, $ErrorAction)
    if ($global:K8sTestState.PeeringFailure) { throw 'Simulated peering failure' }
    return @{ ProvisioningState = 'Succeeded' }
}
function Start-Sleep {
    param($Seconds)
    $global:K8sTestState.SleepCalls += $Seconds
}
function Invoke-AzRestMethod {
    param($Path, $Method, $Payload, $ErrorAction)
    if ($Method -eq 'GET' -and $global:K8sTestState.ReadFailures.Count -gt 0) {
        $status = $global:K8sTestState.ReadFailures[0]
        $global:K8sTestState.ReadFailures = @($global:K8sTestState.ReadFailures | Select-Object -Skip 1)
        return @{ StatusCode = $status; Content = '{}' }
    }
    if ($Method -eq 'PUT') {
        $global:K8sTestState.PutCount++
        if ($global:K8sTestState.DropSubmission) {
            throw [Net.Http.HttpRequestException]::new('Simulated unacknowledged submission')
        }
        $body = $Payload | ConvertFrom-Json
        $global:K8sTestState.Deployments[$Path] = @{ Parameters = $body.properties.parameters; State = 'Succeeded' }
        $global:K8sTestState.GuestParameters = @{
            configuration = $body.properties.parameters.configuration.value
            setupScript = $body.properties.parameters.setupScript.value
        }
        if ($global:K8sTestState.SubmissionFailure) {
            $global:K8sTestState.SubmissionFailure = $false
            throw [Net.Http.HttpRequestException]::new('Simulated lost submission response')
        }
        return @{ StatusCode = 201; Content = '{}' }
    }
    if ($Path -match '/providers/Microsoft.Resources/deployments/') {
        $record = $global:K8sTestState.Deployments[$Path]
        if (-not $record) { return @{ StatusCode = 404; Content = '{}' } }
        if ($global:K8sTestState.StateSteps.Count -gt 0) {
            $record.State = $global:K8sTestState.StateSteps[0]
            $global:K8sTestState.StateSteps = @($global:K8sTestState.StateSteps | Select-Object -Skip 1)
        }
        $body = @{ properties = @{ provisioningState = $record.State; parameters = $record.Parameters } }
    } elseif ($Path -match '/providers/Microsoft.Compute/virtualMachines/(.+)-k8s-master/runCommands/') {
        $prefix = $Matches[1]
        $deploymentPath = ($Path -split '/providers/Microsoft.Compute/')[0] +
            "/providers/Microsoft.Resources/deployments/workstation-${prefix}?api-version=2022-09-01"
        $record = $global:K8sTestState.Deployments[$deploymentPath]
        if (-not $record) { return @{ StatusCode = 404; Content = '{}' } }
        $guestState = $(if ($global:K8sTestState.GuestStateOverride) { $global:K8sTestState.GuestStateOverride } elseif ($global:K8sTestState.GuestFailure) { 'Failed' } elseif ($record.State -eq 'Running') { 'Running' } else { 'Succeeded' })
        $exitCode = $(if ($global:K8sTestState.GuestFailure) { 1 } elseif ($null -ne $global:K8sTestState.ExitCodeOverride) { $global:K8sTestState.ExitCodeOverride } else { 0 })
        $revision = $(if ($global:K8sTestState.GuestRevisionOverride) { $global:K8sTestState.GuestRevisionOverride } else { $record.Parameters.setupRevision.value })
        $body = @{
            tags = @{ microhackSetupRevision = $revision }
            properties = @{
                parameters = @(@{
                    name = 'MICROHACK_ATTEMPT_ID'
                    value = $(if ($global:K8sTestState.GuestAttemptOverride) { $global:K8sTestState.GuestAttemptOverride } else { $record.Parameters.attemptId.value })
                })
                instanceView = @{
                    executionState = $guestState
                    exitCode = $exitCode
                    error = $(if ($global:K8sTestState.GuestFailure) { "Simulated guest provisioning failure $($record.Parameters.configuration.value.admin_password)" } else { '' })
                    output = 'MICROHACK_PHASE=Verify workstation'
                }
            }
        }
    } else {
        throw "Unexpected test ARM path '$Path'."
    }
    return @{ StatusCode = 200; Content = ($body | ConvertTo-Json -Depth 50 -Compress) }
}
function Invoke-MhhDeploymentWithRegionFallback {
    param($PreferredLocations, $ResourceGroupName, $RgOwnerEntraObjectIds, $TemplateFile, $TemplateParameterObject, $Tag)
    $global:K8sTestState.Calls += @{ Group = $ResourceGroupName; Owners = $RgOwnerEntraObjectIds; Parameters = $TemplateParameterObject; Template = (Split-Path $TemplateFile -Leaf) }
    $global:K8sTestState.Groups[$ResourceGroupName] = @{ ResourceGroupName = $ResourceGroupName; Tags = $Tag.Clone() }
    $outputs = switch (Split-Path $TemplateFile -Leaf) {
        'shared.bicep' { @{ bastionName = 'mh-k8s-bastion' } }
        'exercise.bicep' { @{ acrName = $TemplateParameterObject.acrName; workspaceName = $TemplateParameterObject.workspaceName } }
        'main.bicep' { @{
            spokeVnetId = 'test-spoke'
            workstationId = "/subscriptions/$($global:K8sTestState.Subscription)/resourceGroups/$ResourceGroupName/providers/Microsoft.Compute/virtualMachines/$($TemplateParameterObject.workstationName)"
        } }
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
    if ($args -contains 'bicep') { '{"resources":[]}' }
    elseif ($args -contains 'vm' -and $args -contains 'list') { ConvertTo-Json -InputObject @($global:K8sTestState.ExistingVms) -Depth 10 -Compress }
    elseif ($args -contains 'resource' -and $args -contains 'list') { ConvertTo-Json -InputObject @($global:K8sTestState.ExistingExerciseResources) -Depth 10 -Compress }
    elseif ($args -contains 'show') { '{"peeringState":"Connected"}' }
    else { '[]' }
    $global:LASTEXITCODE = 0
}
try {
    $prefixes = @()
    foreach ($user in @($script:user1, $script:user2)) {
        $global:K8sTestState.Calls = @()
        $parameters = @{
            DeploymentType = $defaults.deploymentType
            SubscriptionId = $script:subscription
            ResourceGroupName = $(if ($user -eq $script:user1) { 'rg-labuser-0009' } else { 'rg-labuser-0020' })
            PreferredLocation = @('germanywestcentral')
            AllowedEntraUserIds = @($user)
        }
        $credentials = @(& (Join-Path $root 'deploy-lab.ps1') @parameters)
        $calls = $global:K8sTestState.Calls
        Assert-Test ($calls.Count -eq 2) 'Expected separate exercise and on-prem deployments.'
        Assert-Test ($calls[0].Group -eq $parameters.ResourceGroupName) 'Exercises must use the Console group.'
        Assert-Test ($calls[1].Group -ne $parameters.ResourceGroupName) 'VMs must use a separate group.'
        Assert-Test ($calls[1].Group -eq "$($parameters.ResourceGroupName)-onprem") 'On-prem RG name must derive from the exercise RG, not the user hash.'
        $expectedWorkstation = $parameters.ResourceGroupName -replace '^rg-', ''
        Assert-Test ($calls[1].Parameters.workstationName -eq $expectedWorkstation) 'Workstation VM must use the labuser name.'
        $expectedAcr = 'acr' + ($expectedWorkstation -replace '-', '') +
            (Get-MhhStableHash -Value @($script:subscription, $parameters.ResourceGroupName) -Length 12).Substring(0, 8)
        $expectedWorkspace = "$expectedWorkstation-law"
        Assert-Test ($calls[0].Parameters.acrName -eq $expectedAcr) 'ACR must use the readable participant name and stable eight-character suffix.'
        Assert-Test ($calls[0].Parameters.acrName -cmatch '^acr[a-z0-9]{2,47}$') 'ACR name must satisfy Azure character and length limits.'
        Assert-Test ($calls[0].Parameters.workspaceName -eq $expectedWorkspace) 'Workspace must use the readable participant name.'
        Assert-Test (@($credentials | Where-Object { $_.HackboxCredential.name -eq 'Container Registry' })[0].HackboxCredential.value -eq $expectedAcr) 'Dashboard must publish the actual ACR name.'
        Assert-Test (@($credentials | Where-Object { $_.HackboxCredential.name -eq 'Log Analytics Workspace' })[0].HackboxCredential.value -eq $expectedWorkspace) 'Dashboard must publish the actual workspace name.'
        Assert-Test (@($credentials | Where-Object { $_.HackboxCredential.name -eq 'Workstation VM' })[0].HackboxCredential.value -eq $expectedWorkstation) 'Dashboard must show the labuser workstation name.'
        Assert-Test (@($credentials | Where-Object { $_.HackboxCredential.name -eq 'Workstation Resource ID' })[0].HackboxCredential.value -eq "/subscriptions/$script:subscription/resourceGroups/$($calls[1].Group)/providers/Microsoft.Compute/virtualMachines/$expectedWorkstation") 'Dashboard resource ID must reference the renamed workstation in the correct RG and subscription.'
        Assert-Test ($calls[1].Owners -contains $user) 'The extra group must grant participant Owner.'
        $configuration = $global:K8sTestState.GuestParameters.configuration
        Assert-Test ($configuration.resource_group -eq $parameters.ResourceGroupName) 'Wrong exercise context.'
        Assert-Test ($configuration.onprem_resource_group -eq $calls[1].Group) 'Wrong on-prem context.'
        Assert-Test ($configuration.acr_name -eq $expectedAcr -and $configuration.workspace_name -eq $expectedWorkspace) 'Guest context must receive the renamed exercise resources.'
        Assert-Test ($credentials.Count -eq 9) "Expected nine participant dashboard credentials; got $($credentials.Count)."
        Assert-Test (@($credentials | Where-Object { $_ -isnot [hashtable] -or -not $_.HackboxCredential.value }).Count -eq 0) 'Invalid dashboard output shape.'
        $prefixes += $calls[1].Parameters.labPrefix
        $global:K8sTestState.PeeringFailure = $true
        Assert-Throws { & (Join-Path $root 'deploy-lab.ps1') @parameters } 'Simulated peering failure'
        Assert-Test ($global:K8sTestState.Calls[-2].Parameters.acrName -eq $expectedAcr) 'An ACR name must remain stable on retry.'
        $global:K8sTestState.PeeringFailure = $false
        $global:K8sTestState.GuestFailure = $true
        Assert-Throws { & (Join-Path $root 'deploy-lab.ps1') @parameters } 'Simulated guest provisioning failure'
        $global:K8sTestState.GuestFailure = $false
    }
    Assert-Test ($prefixes[0] -ne $prefixes[1]) 'Participant resource names must be distinct.'
    $global:K8sTestState.ExistingVms = @(@{ name = "$($prefixes[1])-workstation"; tags = @{ Role = 'workstation' } })
    $beforeConflict = $global:K8sTestState.Calls.Count
    Assert-Throws { & (Join-Path $root 'deploy-lab.ps1') @parameters } 'workstation VM(s)'
    Assert-Test ($global:K8sTestState.Calls.Count -eq $beforeConflict) 'A workstation naming conflict must not create another VM.'
    $global:K8sTestState.ExistingVms = @()
    foreach ($legacyResource in @(
        @{ type = 'Microsoft.ContainerRegistry/registries'; name = 'mh' + (Get-MhhStableHash -Value @($script:subscription, $parameters.ResourceGroupName) -Length 18) }
        @{ type = 'Microsoft.OperationalInsights/workspaces'; name = "$($prefixes[1])-law" }
    )) {
        $global:K8sTestState.ExistingExerciseResources = @($legacyResource)
        $beforeConflict = $global:K8sTestState.Calls.Count
        Assert-Throws { & (Join-Path $root 'deploy-lab.ps1') @parameters } 'legacy exercise resource(s)'
        Assert-Test ($global:K8sTestState.Calls.Count -eq $beforeConflict) 'A legacy registry or workspace must be rejected before any deployment.'
    }
    $global:K8sTestState.ExistingExerciseResources = @(
        @{ type = 'Microsoft.ContainerRegistry/registries'; name = $expectedAcr }
        @{ type = 'Microsoft.OperationalInsights/workspaces'; name = $expectedWorkspace }
    )
    $null = & (Join-Path $root 'deploy-lab.ps1') @parameters
    Assert-Test ($global:K8sTestState.Calls[-2].Parameters.workspaceName -eq $expectedWorkspace) 'Already correctly named resources must allow a rerun.'
    $global:K8sTestState.ExistingExerciseResources = @()
    $parameters.ResourceGroupName = 'rg-' + ('a' * 59)
    $null = & (Join-Path $root 'deploy-lab.ps1') @parameters
    Assert-Test ($global:K8sTestState.Calls[-2].Parameters.acrName.Length -eq 50) 'A long participant name must fit the exact 50-character ACR limit.'
    Assert-Test ($global:K8sTestState.Calls[-2].Parameters.workspaceName.Length -eq 63) 'A workspace at the 63-character Azure limit must deploy.'
    $global:K8sTestState.Groups.Remove($parameters.ResourceGroupName)
    $global:K8sTestState.Groups.Remove("$($parameters.ResourceGroupName)-onprem")
    $parameters.ResourceGroupName = 'rg-' + ('a' * 60)
    Assert-Throws { & (Join-Path $root 'deploy-lab.ps1') @parameters } 'valid Log Analytics workspace name'
    $parameters.ResourceGroupName = 'rg-lab.user'
    Assert-Throws { & (Join-Path $root 'deploy-lab.ps1') @parameters } 'valid Log Analytics workspace name'
    $parameters.ResourceGroupName = 'exercise-legacy'
    $parameters.AllowedEntraUserIds = @($script:user1)
    $legacyName = "$($prefixes[0])-onprem"
    $global:K8sTestState.Groups[$legacyName] = @{ ResourceGroupName = $legacyName; Tags = @{} }
    $beforeConflict = $global:K8sTestState.Calls.Count
    Assert-Throws { & (Join-Path $root 'deploy-lab.ps1') @parameters } 'Cleanup required'
    Assert-Test ($global:K8sTestState.Calls.Count -eq $beforeConflict) 'A naming conflict must fail before any infrastructure deployment.'
    Assert-Test (-not $global:K8sTestState.Groups.ContainsKey('exercise-legacy-onprem')) 'Naming conflict must not create parallel resources.'
    $global:K8sTestState.Groups.Remove($legacyName)
    $parameters.ResourceGroupName = 'x' * 84
    Assert-Throws { & (Join-Path $root 'deploy-lab.ps1') @parameters } 'too long'
    $parameters.DeploymentType = 'subscription'
    Assert-Throws { & (Join-Path $root 'deploy-lab.ps1') @parameters } 'requires a resource group'

    $setupParameters = @{
        SubscriptionId = $script:subscription
        ResourceGroupName = 'poll-test-onprem'
        LabPrefix = 'polltest'
        SetupScript = 'echo setup'
        Configuration = @{ admin_password = 'test-secret'; resource_group = 'poll-test' }
        PollIntervalSeconds = 0
    }
    $global:K8sTestState.SubmissionFailure = $true
    $global:K8sTestState.ReadFailures = @(503, 429)
    $global:K8sTestState.StateSteps = @('Running', 'Running', 'Succeeded')
    $before = $global:K8sTestState.PutCount
    Invoke-K8sWorkstationSetup @setupParameters
    Assert-Test ($global:K8sTestState.PutCount -eq $before + 1) 'A lost submission response must not trigger a second PUT.'
    Assert-Test ($global:K8sTestState.SleepCalls -contains 5 -and $global:K8sTestState.SleepCalls -contains 10) 'Transient reads must use bounded backoff.'
    $before = $global:K8sTestState.PutCount
    Invoke-K8sWorkstationSetup @setupParameters
    Assert-Test ($global:K8sTestState.PutCount -eq $before) 'A successful matching setup must not be executed again.'
    $setupParameters.Configuration = @{ resource_group = 'poll-test'; admin_password = 'test-secret' }
    Invoke-K8sWorkstationSetup @setupParameters
    Assert-Test ($global:K8sTestState.PutCount -eq $before) 'Configuration key ordering must not change the setup revision.'
    $global:K8sTestState.StateSteps = @('Running', 'Running', 'Succeeded')
    Invoke-K8sWorkstationSetup @setupParameters
    Assert-Test ($global:K8sTestState.PutCount -eq $before) 'An active matching execution must be observed without restarting it.'
    $setupParameters.SetupScript = 'echo changed'
    $global:K8sTestState.StateSteps = @('Running')
    Assert-Throws { Invoke-K8sWorkstationSetup @setupParameters } 'older workstation deployment is still active'
    Assert-Test ($global:K8sTestState.PutCount -eq $before) 'Changed setup must not replace an active execution.'
    $global:K8sTestState.StateSteps = @('Succeeded')
    Invoke-K8sWorkstationSetup @setupParameters
    Assert-Test ($global:K8sTestState.PutCount -eq $before + 1) 'Changed setup must run after the old execution completes.'
    $setupParameters.SetupScript = 'echo changed again'
    $global:K8sTestState.GuestStateOverride = 'Running'
    $global:K8sTestState.StateSteps = @('Failed')
    Assert-Throws { Invoke-K8sWorkstationSetup @setupParameters } 'duplicate execution'
    Assert-Test ($global:K8sTestState.PutCount -eq $before + 1) 'Failed ARM metadata must not cause a second command while the guest is running.'
    $global:K8sTestState.GuestStateOverride = $null
    $setupParameters.SetupScript = 'echo changed'
    $global:K8sTestState.StateSteps = @('Succeeded')
    $global:K8sTestState.GuestFailure = $true
    Assert-Throws { Invoke-K8sWorkstationSetup @setupParameters } 'Workstation setup failed' 'test-secret'
    $global:K8sTestState.GuestFailure = $false
    $global:K8sTestState.ExitCodeOverride = 7
    Assert-Throws { Invoke-K8sWorkstationSetup @setupParameters } 'without exit code 0'
    $global:K8sTestState.ExitCodeOverride = $null
    $global:K8sTestState.StateSteps = @('Succeeded', 'Failed')
    Assert-Throws { Invoke-K8sWorkstationSetup @setupParameters } 'Workstation setup failed'
    $global:K8sTestState.StateSteps = @('Running')
    $setupParameters.TimeoutSeconds = 0
    Assert-Throws { Invoke-K8sWorkstationSetup @setupParameters } 'Timed out observing'
    $global:K8sTestState.StateSteps = @('Succeeded')
    $global:K8sTestState.GuestRevisionOverride = 'stale-revision'
    Assert-Throws { Invoke-K8sWorkstationSetup @setupParameters } 'Timed out observing'
    $global:K8sTestState.GuestRevisionOverride = $null
    $global:K8sTestState.GuestAttemptOverride = 'stale-attempt'
    Assert-Throws { Invoke-K8sWorkstationSetup @setupParameters } 'Timed out observing'
    $global:K8sTestState.GuestAttemptOverride = $null
    $global:K8sTestState.ReadFailures = @(403)
    $readsBefore = $global:K8sTestState.SleepCalls.Count
    Assert-Throws { Invoke-K8sWorkstationSetup @setupParameters } 'HTTP 403'
    Assert-Test ($global:K8sTestState.SleepCalls.Count -eq $readsBefore) 'Authorization failures must not be retried.'
    $global:K8sTestState.ReadFailures = @(503, 503, 503, 503)
    Assert-Throws { Invoke-K8sWorkstationSetup @setupParameters } 'HTTP 503'
    $setupParameters.ResourceGroupName = 'unacknowledged-onprem'
    $global:K8sTestState.DropSubmission = $true
    $before = $global:K8sTestState.PutCount
    Assert-Throws { Invoke-K8sWorkstationSetup @setupParameters } 'Timed out observing'
    Assert-Test ($global:K8sTestState.PutCount -eq $before + 1) 'An unacknowledged write must never be blindly replayed.'
    $global:K8sTestState.DropSubmission = $false
    function global:bicep {
        '{"resources":[]}'
        $global:K8sTestState.UsedStandaloneCompiler = $true
        $global:LASTEXITCODE = 0
    }
    try {
        $setupParameters.ResourceGroupName = 'standalone-compiler-onprem'
        Invoke-K8sWorkstationSetup @setupParameters
        Assert-Test $global:K8sTestState.UsedStandaloneCompiler 'The Console image standalone Bicep compiler should be preferred.'
    } finally {
        Remove-Item Function:\bicep
    }
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
$exerciseGroups = @('rg-labuser-0009', 'rg-labuser-0020')
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
    $workstationVm = @($template.resources | Where-Object { $_.type -eq 'Microsoft.Compute/virtualMachines' -and -not $_.copy })
    Assert-Test ($workstationVm.Count -eq 1 -and $workstationVm[0].name -eq "[parameters('workstationName')]") 'Windows VM resource must use the explicit workstation name.'
    Assert-Test ($template.variables.vmNames.Contains("parameters('workstationName')")) 'Shutdown schedules must include the renamed workstation.'
    $guestTemplate = Get-Content (Join-Path $temporary 'workstation-setup.json') -Raw | ConvertFrom-Json
    Assert-Test ($guestTemplate.parameters.configuration.type -eq 'secureObject') 'Guest configuration must be a secure object.'
    $runCommand = @($guestTemplate.resources | Where-Object { $_.type -eq 'Microsoft.Compute/virtualMachines/runCommands' })
    Assert-Test ($runCommand.Count -eq 1 -and $runCommand[0].properties.treatFailureAsDeploymentFailure) 'Guest failures must fail ARM deployment.'
    Assert-Test (-not $runCommand[0].properties.asyncExecution) 'ARM completion must still reflect actual guest completion.'
    Assert-Test ($runCommand[0].properties.parameters[0].value -eq "[parameters('attemptId')]") 'New executions need an explicit identifier.'
    Assert-Test ($runCommand[0].tags.microhackSetupRevision -eq "[parameters('setupRevision')]") 'Observed guest results must belong to the requested setup revision.'
    Assert-Test (@($template.resources | Where-Object { $_.type -match 'registries|workspaces' }).Count -eq 0) 'On-prem template must not create exercise resources.'
    $exerciseTemplate = Get-Content (Join-Path $temporary 'exercise.json') -Raw | ConvertFrom-Json
    $workspace = @($exerciseTemplate.resources | Where-Object { $_.type -eq 'Microsoft.OperationalInsights/workspaces' })
    $registry = @($exerciseTemplate.resources | Where-Object { $_.type -eq 'Microsoft.ContainerRegistry/registries' })
    Assert-Test ($workspace.Count -eq 1 -and $workspace[0].name -eq "[parameters('workspaceName')]") 'Workspace Bicep resource must use the explicit participant name.'
    Assert-Test ($registry.Count -eq 1 -and $registry[0].name -eq "[parameters('acrName')]") 'Registry Bicep resource must use the explicit participant name.'
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
