[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    [string[]]$ExerciseResourceGroupNames = @(),
    [switch]$RemoveSharedResources
)

. (Join-Path $PSScriptRoot 'common.ps1')
Assert-K8sContext $SubscriptionId

function Remove-K8sGroup {
    param([string]$Name)
    Update-MhhToken | Out-Null
    $result = Remove-MhhResourceGroup -ResourceGroupName $Name
    if (-not $result.ManifestCaptured -or $result.Errors.Count -gt 0 -or $result.SoftDeletedResidual.Count -gt 0) {
        throw "Cleanup of '$Name' is incomplete: $($result.Errors -join '; '). Inspect the remaining resources before retrying."
    }
}

foreach ($name in ($ExerciseResourceGroupNames | Select-Object -Unique)) {
    $exercise = Get-AzResourceGroup -Name $name -ErrorAction Stop
    if (-not $exercise.Tags -or $exercise.Tags['microhack'] -ne 'arc-kubernetes' -or -not $exercise.Tags['microhackOnpremGroup']) {
        throw "Resource group '$name' is not a marked Kubernetes exercise resource group."
    }
    $onpremName = $exercise.Tags['microhackOnpremGroup']
    $onprem = Get-AzResourceGroup -Name $onpremName -ErrorAction SilentlyContinue
    if ($onprem -and (-not $onprem.Tags -or $onprem.Tags['microhack'] -ne 'arc-kubernetes' -or
        $onprem.Tags['microhackExerciseGroup'] -ne $name -or
        $onprem.Tags['microhackUserId'] -ne $exercise.Tags['microhackUserId'])) {
        throw "The on-prem resource group '$onpremName' does not match '$name'."
    }
    if ($PSCmdlet.ShouldProcess("$name and $onpremName", 'Delete both participant resource groups')) {
        if ($onprem) {
            Remove-K8sGroup $onpremName
        }
        Remove-K8sGroup $name
    }
}

if ($RemoveSharedResources) {
    $remaining = @(Get-AzResourceGroup -ErrorAction Stop | Where-Object {
        $_.Tags -and $_.Tags['microhack'] -eq 'arc-kubernetes' -and $_.ResourceGroupName -ne $script:SharedGroupName
    })
    if ($remaining.Count -gt 0) {
        throw 'Participant resource groups remain. Clean up every participant before deleting the shared Bastion.'
    }
    $shared = Get-AzResourceGroup -Name $script:SharedGroupName -ErrorAction Stop
    if (-not $shared.Tags -or $shared.Tags['microhack'] -ne 'arc-kubernetes') {
        throw 'The shared resource group does not belong to this MicroHack.'
    }
    if ($PSCmdlet.ShouldProcess($script:SharedGroupName, 'Delete shared Bastion infrastructure')) {
        Remove-K8sGroup $script:SharedGroupName
    }
}
