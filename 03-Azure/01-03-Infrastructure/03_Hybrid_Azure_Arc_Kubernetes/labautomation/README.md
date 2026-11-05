# Hackbox Console - Azure Arc-enabled Kubernetes

This is the Console deployment path. The existing [lab](../lab/readme.md)
Terraform/Ansible deployment remains unchanged as a manual fallback.

## Layout and scope

Console runs [shared-deploy-lab.ps1](shared-deploy-lab.ps1) once per subscription,
then [deploy-lab.ps1](deploy-lab.ps1) once per participant in parallel.

| Scope | Contents |
| --- | --- |
| Shared RG `mh-k8s-shared` | Standard Bastion, hub VNet and public IP |
| Exercise RG supplied by Console | ACR, Log Analytics workspace, later Arc/exercise resources |
| Separate `<lab-prefix>-onprem` RG | Three K3s VMs, Windows workstation, spoke VNet, NSGs, NAT gateway and outbound public IP |

The lab prefix is derived from the participant's Entra object ID, not a guessed
LabUser number. Both participant RG names and all access information are
returned to the dashboard. No participant VM has a public IP or public
management port. NAT provides explicit outbound connectivity for package and
container downloads, including subscriptions where default outbound access is disabled.

**Permissions:** [lab-defaults.json](lab-defaults.json) deliberately uses
`resourcegroup-with-subscriptionowner`, allowing the subscription-level
Defender for Containers configuration in challenge 2. Participants have Owner
on the shared subscription and **are not RBAC-isolated from other participants**.
Use disposable training subscriptions only. For RG-level isolation, change
the value to `resourcegroup`; the coach must then perform the subscription-level
Defender configuration. The script explicitly grants participants Owner on
their additional on-prem RG in either mode. Shared Bastion resources get Reader
assignments through [shared.bicep](shared.bicep).

Resource group tags include `SecurityControl=Ignore`. Existing tags are merged.
The exercise and on-prem groups carry reciprocal reference tags for cleanup.
Shared tags persist the per-user network assignments, avoiding overlapping
networks and preventing addresses from changing when the participant list is
reordered or extended. This implementation supports at most **32 participants
per subscription** to leave room under Azure's 50-tag limit. The default is four.

## Bicep and provisioning

- [shared.bicep](shared.bicep) provisions the shared Bastion.
- [exercise.bicep](exercise.bicep) provisions ACR and Log Analytics.
- [main.bicep](main.bicep) provisions only the simulated on-prem environment.
- [workstation-setup.bicep](workstation-setup.bicep) executes the Ansible and
  readiness phase separately, refreshing the Console token between long phases.
- [hub-peering.bicep](hub-peering.bicep) adds the reverse hub peering under a
  subscription-specific Console lock. The spoke peering belongs to the on-prem RG.

Infrastructure RG deployments use `Invoke-MhhDeploymentWithRegionFallback`, passing
participant IDs for Owner restoration on both participant groups. Exercise and
VM resources may fall back independently; the WSL context records the actual
exercise region. The guest configuration and shared hub peering use normal incremental deployments
and fail explicitly if they cannot complete. A disconnected reverse peering left
by an on-prem RG recycle is removed and rebuilt under the hub lock.

Passwords and the K3s token are stable across retries and are passed in secure
ARM parameters and protected guest configuration, never public template outputs.
K3s bootstrap commands are bounded to 30 minutes. The synchronous managed
Run Command for workstation configuration is bounded to 60 minutes and uses
`treatFailureAsDeploymentFailure`; a failed playbook or readiness check fails
the lab rather than publishing credentials for an unready workstation.

The VM sizes remain `Standard_D4ds_v6` (four VMs / **16 vCPUs per participant**),
with Ubuntu 22.04, Windows 11 24H2 Pro and K3s `v1.33.6+k3s1`.
WSL2 requires nested virtualization support in the selected VM SKU. Verify
regional VM-family and total vCPU quotas, image availability and Windows
licensing eligibility before the event. VMs shut down at 18:00 Munich time;
there is no automatic startup. Start all four again if provisioning runs overnight.

The daily cost fields are **planning placeholders, not verified price quotes**.
Review regional VM, disk, NAT, Bastion and consumption pricing before booking.
Enabling Defender in the exercises adds charges not included in these placeholders.
The scripts do not enable the paid Defender plan automatically.

## Reusing Ansible without changing the fallback

Yes: [the original playbook](../lab/ansible/playbook-workstation.yml) stays in
`lab/ansible` and is executed unchanged. Its Terraform inventory and Bastion
tunnel launcher cannot be used unchanged: Console executes one participant at
a time in separate processes, and the documented Console image has no Ansible.

Instead, the participant K3s master runs Ansible in a private Python virtual
environment against the workstation's private WinRM HTTPS endpoint. Only that
master IP is allowed to reach WinRM. The existing relative layout of the
playbook and [WSL setup script](../lab/scripts/setup-wsl-tools.sh) is preserved
on the guest. [requirements.txt](requirements.txt) pins Python dependencies
compatible with Ubuntu 22.04; the existing collection requirements are retained.

[configure-workstation.sh](configure-workstation.sh) adds an inventory and then
runs [verify-workstation.yml](verify-workstation.yml) after the original playbook.
This ensures VS Code's WSL extension is installed after the provisioning reboots
(the original playbook tolerates failure of that task), checks Git and the WSL CLI tools, installs
kubeconfig for the interactive WSL user, and writes `~/.microhack-k8s.env`.
Finally, exactly three K3s nodes must be `Ready`. The cluster is **not** connected
to Arc: that remains challenge 1.

Console only needs the `labautomation` package at runtime. The archive
`lab-assets.zip` contains byte-for-byte copies of six existing fallback assets.
Its source of truth remains `lab`; it does not fetch mutable scripts from
GitHub during deployment. After changing a source asset, rebuild and commit
the archive:

```powershell
.\build-assets.ps1
.\tests\offline.Tests.ps1
```

The packaging step does not modify any file in `lab`. Only bootstrap rendering
removes Terraform escaping, substitutes the original parameters and makes
GPG key creation non-interactive for retries.

## Participant access

1. In the Azure portal, open the dashboard's **Bastion Name** in its shared RG.
2. Connect to **Workstation VM** in **On-prem Resource Group**, using the returned
   VM username/password.
3. Open a WSL terminal and run:

   ```bash
   source ~/.microhack-k8s.env
   az login
   kubectl get nodes
   ```

4. Continue with [challenge 1](../challenges/challenge-01.md). The walkthroughs
   honor the environment file while retaining the manual fallback defaults.
   Use the dashboard's ACR name, not a numeric `<xy>mhacr` example.

## Validation and pilot

Offline tests parse every PowerShell file, compile every Bicep template, check
archive/source equality, simulate the shared and participant hooks and verify
scope separation, credential output, stable network assignments and error paths.
They require PowerShell 7 and Azure CLI with Bicep installed.

For a platform-like local test use the
[documented adminpwsh image](https://github.com/skiddder/MicroHack/blob/main/99-MicroHack-Template/labautomation/README.md#local-testing).
Authenticate locally and run the shared hook first, then the participant hook,
passing the actual subscription, existing exercise RG and participant object ID.
Local helper stand-ins are not identical to Console's production helpers.

**Before Munich, a real Console pilot is required:** two parallel participants,
working Bastion RDP, WSL2 after reboot, three Ready nodes, Arc onboarding,
Defender permissions, and a retry after partial failure. Compilation and mock
tests cannot prove Azure capacity, image licensing, package download availability
or first-launch WSL behavior.

## Cleanup

Console knows its exercise RG, but the extra on-prem RG and shared RG are
created by our scripts. **Do not assume scope-only Console cleanup removes them.**
After the event, run [cleanup.ps1](cleanup.ps1) from an authenticated admin
environment with the Console helper module, listing the exercise RGs explicitly:

```powershell
.\cleanup.ps1 -SubscriptionId '<subscription-id>' `
  -ExerciseResourceGroupNames @('<exercise-rg-1>', '<exercise-rg-2>') -WhatIf

.\cleanup.ps1 -SubscriptionId '<subscription-id>' `
  -ExerciseResourceGroupNames @('<exercise-rg-1>', '<exercise-rg-2>') `
  -RemoveSharedResources
```

The script validates reciprocal tags, asks for confirmation, removes both groups
using `Remove-MhhResourceGroup`, and only deletes shared Bastion after all marked
participant groups are gone. If Console has already deleted an exercise RG,
inspect its on-prem partner via `microhackExerciseGroup` / `microhackUserId` tags
and remove that explicitly after verifying ownership. The archive and source
files have no Terraform-state dependency.
