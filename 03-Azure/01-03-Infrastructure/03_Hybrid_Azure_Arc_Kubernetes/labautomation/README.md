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
| Separate `<exercise-rg>-onprem` RG | Three K3s VMs, Windows workstation, spoke VNet, NSGs, NAT gateway and outbound public IP |

The lab prefix is derived from the participant's Entra object ID, not a guessed
LabUser number. K3s VM and cluster network names retain this prefix, but the on-prem RG name is
derived from the Console exercise RG: `rg-labuser-0020` becomes
`rg-labuser-0020-onprem`. Both participant RG names and all access information are
returned to the dashboard. The workstation Azure VM name is derived by removing
the leading `rg-`: **`labuser-0020`**, with `labuser-0020-nic` and
`labuser-0020-nsg`. Its shutdown schedule and returned resource ID reference
this name; the Windows computer name remains `mhworkstation`.
The Log Analytics workspace uses **`labuser-0020-law`**. The globally named
container registry uses **`acrlabuser0020<8-character-hash>`**: the participant
name is lowercased with hyphens removed, followed by a stable suffix derived
from the subscription ID and exercise RG. The ACR participant stem is limited
to 39 characters so the full name fits Azure's 50-character limit. The Console
hash helper requires at least 12 characters; the deployment requests 12 and
uses the first eight for the ACR suffix. A global
name collision fails deployment rather than choosing an unstable alternative.
The dashboard and WSL context expose the actual names; challenges 2 and 4 use
`workspace_name`, retaining their original name defaults for the Terraform fallback.
No participant VM has a public IP or public
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
and fail explicitly if they cannot complete. The workstation ARM deployment is
submitted through a short REST PUT and observed through separate GET requests;
the Console no longer holds a synchronous connection for the entire Ansible run.
Before either participant RG deployment, the script checks the participant's
reverse hub peering under the subscription-specific hub lock. A stale peering
to the old hash-named VNet is removed only after an ARM GET confirms that VNet
no longer exists (HTTP 404), even if the cached peering state still says Connected.
A Disconnected peering to the current spoke is also removed. Deletion is
observed for up to five minutes before infrastructure submission, avoiding an
address-space conflict with the old hub reference. Existing legacy VNets and
unrecognized targets cause an explicit failure; other participants' peerings
and healthy current connections are not modified. Authorization/read failures
never count as evidence that a VNet is missing.
The same check runs again before publishing the reverse peering after guest
setup, handling disconnected references left by an on-prem RG recycle.

Passwords and the K3s token are stable across retries and are passed in secure
ARM parameters and protected guest configuration, never public template outputs.
K3s bootstrap commands are bounded to 30 minutes. The managed Run Command remains
bounded to 60 minutes and uses `treatFailureAsDeploymentFailure`, so Azure ARM
only reports completion after the guest is done. Console polls ARM and the guest
every 30 seconds, refreshes credentials before requests and reports state/elapsed
time. Observation is bounded to 75 minutes and does not cancel server-side work.
A failed playbook, failed readiness check or nonzero guest exit code fails the
lab rather than publishing credentials for an unready workstation.

Transient read failures (transport errors, HTTP 408/429/500/502/503/504) get
bounded retries. An interrupted submission response is reconciled using its
execution ID; it is never blindly resubmitted. A re-run recognizes matching
active or successful setup content and resumes observation without re-executing
Ansible. Changed content is not submitted over an active older execution.
Only after matching ARM **and** guest success with exit code zero does the script
repair/create hub peering and publish dashboard credentials.

**Existing hash-named RGs:** the script checks for `<lab-prefix>-onprem` and
other on-prem RGs tagged as belonging to this exercise RG before making changes.
If found, it stops with a cleanup-required message. It does not rename/delete
the old RG or create a second on-prem environment. Use the existing
[cleanup script](cleanup.ps1) via the old exercise RG reference tags before
deploying the new naming scheme. Azure resource groups cannot be renamed.
An existing hash-named workstation in the desired on-prem RG is also rejected
before deployment, preventing an incremental ARM update from leaving two workstations.
The same preflight rejects the previous hash-named ACR and workspace in the
exercise RG. It does not silently leave old resources behind or automatically
delete them. The old lab must be cleaned up before switching naming schemes.

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
compatible with Ubuntu 22.04. [collections.yml](collections.yml) pins
`ansible.windows` 2.8.0 and `chocolatey.chocolatey` 1.5.3, both requiring
Ansible >=2.15 and supporting the pinned 2.17.14 core.
The Console adapter pins WSL kubectl to `v1.33.6`, matching K3s, instead of
downloading the latest incompatible client. The original source assets remain unchanged.

[configure-workstation.sh](configure-workstation.sh) adds an inventory and then
runs [verify-workstation.yml](verify-workstation.yml) after the original playbook.
This ensures VS Code's WSL extension is installed after the provisioning reboots
(the original playbook tolerates failure of that task), checks Git, the WSL CLI tools
and kubectl's minor version, installs
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
GPG key creation non-interactive for retries. WSL script rendering additionally
replaces the latest-kubectl lookup with the matching K3s client version.

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
scope separation, credential output, stable network assignments, legacy naming
conflicts, interrupted submissions, transient status errors, recovery without
duplicate guest execution, and failure/timeout paths.
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
