$ErrorActionPreference = 'Stop'
$script:SharedGroupName = 'mh-k8s-shared'

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
        Replace('${k3s_version}', 'v1.33.6+k3s1').
        Replace('${cluster_token}', $ClusterToken).
        Replace('${master_ip}', $MasterIp).
        Replace('$${', '${').
        Replace('gpg --dearmor -o', 'gpg --batch --yes --dearmor -o')
    # Bound the legacy scripts' polling loops and package operations.
    return ConvertTo-K8sBase64 ("#!/bin/bash`nset -euo pipefail`nexport DEBIAN_FRONTEND=noninteractive`ntimeout 1800 bash <<'MICROHACK_BOOTSTRAP'`n$text`nMICROHACK_BOOTSTRAP`n")
}

function Get-K8sWorkstationScript {
    $script = Get-Content (Join-Path $PSScriptRoot 'configure-workstation.sh') -Raw
    $assets = @{
        '__PLAYBOOK__' = Get-K8sAsset 'ansible\playbook-workstation.yml'
        '__COLLECTIONS__' = Get-K8sAsset 'ansible\requirements.yml'
        '__WSL_TOOLS__' = Get-K8sAsset 'scripts\setup-wsl-tools.sh'
        '__VERIFY__' = Get-Content (Join-Path $PSScriptRoot 'verify-workstation.yml') -Raw
        '__PYTHON_REQUIREMENTS__' = Get-Content (Join-Path $PSScriptRoot 'requirements.txt') -Raw
    }
    foreach ($key in $assets.Keys) {
        $script = $script.Replace($key, (ConvertTo-K8sBase64 $assets[$key]))
    }
    return $script.Replace("`r`n", "`n")
}
