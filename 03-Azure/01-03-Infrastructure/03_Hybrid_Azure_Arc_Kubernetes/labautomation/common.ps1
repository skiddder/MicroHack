$ErrorActionPreference = 'Stop'
$script:SharedGroupName = 'mh-k8s-shared'
$script:K3sVersion = 'v1.33.6+k3s1'

function Get-K8sRegions {
    param([string[]]$Locations)
    $regions = @($Locations | ForEach-Object { $_ -split ',' } |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { $_ } | Select-Object -Unique)
    if ($regions.Count -eq 0) {
        throw 'At least one preferred Azure region is required.'
    }
    return $regions
}

function Invoke-K8sAz {
    param([string[]]$Arguments)
    Update-MhhToken | Out-Null
    $output = & az @Arguments --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command '$($Arguments[0..2] -join ' ')' failed (exit $LASTEXITCODE)."
    }
    if ($output) {
        return ($output -join "`n") | ConvertFrom-Json
    }
}

function Assert-K8sContext {
    param([string]$SubscriptionId)
    $context = Get-AzContext -ErrorAction Stop
    if ($null -eq $context -or $context.Subscription.Id -ne $SubscriptionId) {
        throw "The authenticated Azure context must point at subscription '$SubscriptionId'."
    }
}

function ConvertTo-K8sBase64 {
    param([string]$Text)
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-K8sAsset {
    param([string]$RelativePath)
    $archivePath = Join-Path $PSScriptRoot 'lab-assets.zip'
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        throw 'lab-assets.zip is missing. Run build-assets.ps1 before publishing the Console automation.'
    }
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $entry = $archive.GetEntry($RelativePath.Replace('\', '/'))
        if ($null -eq $entry) {
            throw "The packaged lab asset '$RelativePath' is missing."
        }
        $reader = [IO.StreamReader]::new($entry.Open())
        try {
            return $reader.ReadToEnd().Replace("`r`n", "`n")
        } finally {
            $reader.Dispose()
        }
    } finally {
        $archive.Dispose()
    }
}

function Get-K8sBootstrap {
    param(
        [ValidateSet('master', 'worker')]
        [string]$Role,
        [string]$ClusterToken,
        [string]$MasterIp
    )
    if ($ClusterToken -notmatch '^[A-Za-z0-9]+$') {
        throw 'The K3s token must be alphanumeric for safe shell template substitution.'
    }
    $text = Get-K8sAsset "k3s-$Role-setup.sh"
    $text = $text.Replace('${admin_user}', 'mhadmin').
        Replace('${k3s_version}', $script:K3sVersion).
        Replace('${cluster_token}', $ClusterToken).
        Replace('${master_ip}', $MasterIp).
        Replace('$${', '${').
        Replace('gpg --dearmor -o', 'gpg --batch --yes --dearmor -o')
    $preparation = @'
echo "Waiting for cloud-init to finish before starting package operations..."
if timeout 600 cloud-init status --wait --long; then
    echo "cloud-init completed successfully."
else
    status=$?
    echo "cloud-init did not complete successfully (exit $status); refusing to run APT. Inspect /var/log/cloud-init.log and /var/log/cloud-init-output.log." >&2
    exit "$status"
fi
'@
    # Bound the legacy scripts' polling loops and package operations.
    return ConvertTo-K8sBase64 ("#!/bin/bash`nset -euo pipefail`nexport DEBIAN_FRONTEND=noninteractive`ntimeout 1800 bash <<'MICROHACK_BOOTSTRAP'`nset -euo pipefail`n$preparation`n$text`nMICROHACK_BOOTSTRAP`n").Replace("`r`n", "`n")
}

function Get-K8sWorkstationScript {
    $script = Get-Content (Join-Path $PSScriptRoot 'configure-workstation.sh') -Raw
    $wslTools = Get-K8sAsset 'scripts\setup-wsl-tools.sh'
    $versionAssignment = 'KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)'
    if (-not $wslTools.Contains($versionAssignment)) {
        throw 'The packaged WSL tools script changed; update the Console kubectl version adapter before deploying.'
    }
    $kubectlVersion = $script:K3sVersion -replace '\+.*$', ''
    $wslTools = $wslTools.Replace($versionAssignment, "KUBECTL_VERSION=$kubectlVersion").
        Replace('curl -LO ', 'curl -fLO ')
    $assets = @{
        '__PLAYBOOK__' = Get-K8sAsset 'ansible\playbook-workstation.yml'
        '__COLLECTIONS__' = Get-Content (Join-Path $PSScriptRoot 'collections.yml') -Raw
        '__WSL_TOOLS__' = $wslTools
        '__VERIFY__' = Get-Content (Join-Path $PSScriptRoot 'verify-workstation.yml') -Raw
        '__PYTHON_REQUIREMENTS__' = Get-Content (Join-Path $PSScriptRoot 'requirements.txt') -Raw
    }
    foreach ($key in $assets.Keys) {
        $script = $script.Replace($key, (ConvertTo-K8sBase64 $assets[$key]))
    }
    return $script.Replace("`r`n", "`n")
}

function Get-K8sRequestFailure {
    param([Management.Automation.ErrorRecord]$Record)
    $status = 0
    $transportFailure = $false
    for ($exception = $Record.Exception; $exception; $exception = $exception.InnerException) {
        if ($exception.Response -and $exception.Response.StatusCode) {
            $status = [int]$exception.Response.StatusCode
        } elseif ($exception.StatusCode) {
            $status = [int]$exception.StatusCode
        }
        if ($exception -is [Net.Http.HttpRequestException] -or
            $exception -is [Net.WebException] -or
            $exception -is [TimeoutException] -or
            $exception -is [Threading.Tasks.TaskCanceledException]) {
            $transportFailure = $true
        }
    }
    return @{
        StatusCode = $status
        Retryable = $(if ($status) { $status -in @(408, 429, 500, 502, 503, 504) } else { $transportFailure })
    }
}

function Invoke-K8sArmRequest {
    param(
        [string]$Path,
        [ValidateSet('GET', 'PUT')]
        [string]$Method = 'GET',
        [string]$Payload,
        [switch]$AllowNotFound
    )
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        Update-MhhToken | Out-Null
        try {
            $parameters = @{ Path = $Path; Method = $Method; ErrorAction = 'Stop' }
            if ($Method -eq 'PUT') { $parameters.Payload = $Payload }
            $response = Invoke-AzRestMethod @parameters
            if ([int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -ge 300) {
                throw [Net.Http.HttpRequestException]::new(
                    "Azure ARM returned HTTP $($response.StatusCode).", $null, [Net.HttpStatusCode]$response.StatusCode
                )
            }
            if ($response.Content) {
                return $response.Content | ConvertFrom-Json
            }
            return
        } catch {
            $failure = Get-K8sRequestFailure $_
            if ($AllowNotFound -and $Method -eq 'GET' -and $failure.StatusCode -eq 404) { return }
            # Never replay a write whose acceptance is unknown; reconcile its deployment ID instead.
            if ($Method -eq 'PUT' -or -not $failure.Retryable -or $attempt -eq 4) { throw }
            Write-Warning "Transient Azure status request failure (HTTP $($failure.StatusCode)); retry $attempt/3."
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
}

function Repair-K8sHubPeering {
    param(
        [string]$SubscriptionId,
        [string]$LabPrefix,
        [string]$SpokeVnetId
    )
    $arguments = @(
        'network', 'vnet', 'peering', 'list',
        '--resource-group', $script:SharedGroupName, '--vnet-name', 'mh-k8s-hub'
    )
    $name = "to-$LabPrefix"
    $peerings = @(Invoke-K8sAz $arguments)
    $peering = $peerings | Where-Object { $_.name -eq $name }
    if (-not $peering) { return }
    $remoteId = [string]$peering.remoteVirtualNetwork.id
    $legacyId = "/subscriptions/$SubscriptionId/resourceGroups/$LabPrefix-onprem/providers/Microsoft.Network/virtualNetworks/$LabPrefix-k8s-vnet"
    if ($remoteId -notin @($SpokeVnetId, $legacyId)) {
        throw "Unexpected hub peering target '$remoteId' for '$name'. Refusing to modify an unrecognized network."
    }
    if ($remoteId -eq $legacyId) {
        $legacyVnet = Invoke-K8sArmRequest -Path "${remoteId}?api-version=2024-05-01" -AllowNotFound
        if ($legacyVnet) {
            throw "Cleanup required before deployment: hub peering '$name' still references existing legacy VNet '$remoteId'. No legacy network or peering was deleted."
        }
    } elseif ($peering.peeringState -ne 'Disconnected') {
        Write-Host "[peering] Keeping '$name' targeting the current spoke (state=$($peering.peeringState))."
        return
    }
    Write-Host "[peering] Removing stale hub peering '$name' targeting '$remoteId' before deploying its replacement."
    Invoke-K8sAz @(
        'network', 'vnet', 'peering', 'delete', '--resource-group', $script:SharedGroupName,
        '--vnet-name', 'mh-k8s-hub', '--name', $name
    ) | Out-Null
    for ($attempt = 1; $attempt -le 30; $attempt++) {
        $remaining = @(Invoke-K8sAz $arguments | Where-Object { $_.name -eq $name })
        if ($remaining.Count -eq 0) { return }
        if ($attempt -lt 30) { Start-Sleep -Seconds 10 }
    }
    throw "Hub peering '$name' is still present after waiting for deletion. No replacement deployment was submitted by this phase."
}

function Invoke-K8sWorkstationSetup {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$LabPrefix,
        [string]$SetupScript,
        [hashtable]$Configuration,
        [int]$PollIntervalSeconds = 30,
        [int]$TimeoutSeconds = 4500
    )
    $canonical = [ordered]@{}
    foreach ($key in ($Configuration.Keys | Sort-Object)) { $canonical[$key] = $Configuration[$key] }
    $configurationJson = $canonical | ConvertTo-Json -Compress
    $revision = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
        [Text.Encoding]::UTF8.GetBytes("$SetupScript`n$configurationJson")
    )).ToLowerInvariant()
    $groupId = "/subscriptions/$SubscriptionId/resourceGroups/$([Uri]::EscapeDataString($ResourceGroupName))"
    $deploymentPath = "$groupId/providers/Microsoft.Resources/deployments/workstation-${LabPrefix}?api-version=2022-09-01"
    $commandPath = "$groupId/providers/Microsoft.Compute/virtualMachines/$LabPrefix-k8s-master/runCommands/workstation-setup?api-version=2024-07-01&`$expand=instanceView"
    $deployment = Invoke-K8sArmRequest -Path $deploymentPath -AllowNotFound
    $activeStates = @('Accepted', 'Running', 'Creating', 'Updating', 'Canceling')
    $sameRevision = $deployment -and $deployment.properties.parameters.setupRevision.value -eq $revision
    $state = [string]$deployment.properties.provisioningState
    if ($deployment -and -not $sameRevision -and $state -in $activeStates) {
        throw "An older workstation deployment is still active in '$ResourceGroupName'. Wait for it to finish before deploying changed setup content."
    }
    $resume = $sameRevision -and $state -in ($activeStates + @('Succeeded'))
    $started = [DateTime]::UtcNow
    $deadline = $started.AddSeconds($TimeoutSeconds)
    if ($resume) {
        $attemptId = [string]$deployment.properties.parameters.attemptId.value
        if (-not $attemptId) { throw 'The existing workstation deployment has no execution identifier; refusing an ambiguous resume.' }
        Write-Host "[workstation] Resuming server-side deployment in '$ResourceGroupName' (ARM=$state); no guest command is resubmitted."
    } else {
        $existingCommand = Invoke-K8sArmRequest -Path $commandPath -AllowNotFound
        if ($existingCommand -and $existingCommand.properties.instanceView.executionState -notin @('Succeeded', 'Failed', 'TimedOut', 'Canceled')) {
            throw "A guest command is still active or its execution state is unavailable in '$ResourceGroupName'. Refusing to start a duplicate execution."
        }
        $attemptId = [guid]::NewGuid().ToString()
        $templatePath = Join-Path $PSScriptRoot 'workstation-setup.bicep'
        $bicep = Get-Command bicep -ErrorAction SilentlyContinue
        if ($bicep) {
            $compiled = & $bicep build $templatePath --stdout
        } else {
            $compiled = & az bicep build --file $templatePath --stdout --only-show-errors
        }
        if ($LASTEXITCODE -ne 0) { throw 'Compiling the workstation setup template failed.' }
        $payload = @{
            properties = @{
                mode = 'Incremental'
                template = ($compiled -join "`n") | ConvertFrom-Json -AsHashtable
                parameters = @{
                    masterVmName = @{ value = "$LabPrefix-k8s-master" }
                    setupScript = @{ value = $SetupScript }
                    configuration = @{ value = $canonical }
                    setupRevision = @{ value = $revision }
                    attemptId = @{ value = $attemptId }
                }
            }
        } | ConvertTo-Json -Depth 100 -Compress
        Write-Host "[workstation] Submitting ARM deployment in '$ResourceGroupName'; guest execution continues server-side."
        try {
            Invoke-K8sArmRequest -Path $deploymentPath -Method PUT -Payload $payload | Out-Null
        } catch {
            if (-not (Get-K8sRequestFailure $_).Retryable) { throw }
            Write-Warning 'The submission response was interrupted. Checking Azure for this exact execution instead of submitting it again.'
        }
    }
    $ackDeadline = [DateTime]::UtcNow.AddMinutes(10)
    do {
        $deployment = Invoke-K8sArmRequest -Path $deploymentPath -AllowNotFound
        $matchesAttempt = $deployment -and $deployment.properties.parameters.attemptId.value -eq $attemptId
        $elapsed = [int]([DateTime]::UtcNow - $started).TotalSeconds
        if ($matchesAttempt) {
            $state = [string]$deployment.properties.provisioningState
            $command = Invoke-K8sArmRequest -Path $commandPath -AllowNotFound
            $view = $command.properties.instanceView
            $guestAttempt = @($command.properties.parameters | Where-Object { $_.name -eq 'MICROHACK_ATTEMPT_ID' })
            $guestMatches = $command -and $command.tags.microhackSetupRevision -eq $revision -and
                $guestAttempt.Count -eq 1 -and $guestAttempt[0].value -eq $attemptId
            $guestState = $(if ($guestMatches -and $view.executionState) { $view.executionState } else { 'Pending' })
            Write-Host "[workstation] '$ResourceGroupName': ARM=$state guest=$guestState elapsed=${elapsed}s."
            $phases = [regex]::Matches([string]$view.output, '(?m)^MICROHACK_PHASE=([A-Za-z0-9 .-]+)\r?$')
            if ($guestMatches -and $phases.Count -gt 0) {
                Write-Host "[workstation] Last reported phase: $($phases[$phases.Count - 1].Groups[1].Value)."
            }
            if ($state -in @('Failed', 'Canceled') -or
                ($guestMatches -and $guestState -in @('Failed', 'TimedOut', 'Canceled'))) {
                $details = ($deployment.properties.error | ConvertTo-Json -Depth 20 -Compress) +
                    "`n$($view.error)`n$($view.output)"
                foreach ($secret in @($Configuration.admin_password, (ConvertTo-K8sBase64 $configurationJson))) {
                    if ($secret) { $details = $details.Replace($secret, '[REDACTED]') }
                }
                throw "Workstation setup failed in '$ResourceGroupName' (ARM=$state, guest=$guestState, exit=$($view.exitCode)). $details"
            }
            if ($state -eq 'Succeeded' -and $guestMatches -and $guestState -eq 'Succeeded') {
                if ($null -eq $view.exitCode -or $view.exitCode -ne 0) {
                    throw "Workstation execution reported Succeeded without exit code 0 in '$ResourceGroupName'."
                }
                Write-Host "[workstation] Verified successful guest execution in '$ResourceGroupName'; continuing with peering and dashboard credentials."
                return
            }
        } else {
            Write-Host "[workstation] '$ResourceGroupName': waiting for Azure to acknowledge execution $attemptId (${elapsed}s)."
            if ([DateTime]::UtcNow -ge $ackDeadline) {
                throw "Azure did not acknowledge workstation execution '$attemptId'. No duplicate command was submitted. Re-run the lab to reconcile server-side state."
            }
        }
        if ([DateTime]::UtcNow -ge $deadline) {
            throw "Timed out observing workstation setup in '$ResourceGroupName'. The Azure command was not canceled; a re-run resumes the same execution."
        }
        Start-Sleep -Seconds $PollIntervalSeconds
    } while ($true)
}
