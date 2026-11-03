# Hackbox automation: Azure Arc-enabled servers

## Console configuration

Import this MicroHack with `deploymentType = resourcegroup`. The Hackbox Console
controls both the participant count and subscription packing. **Configure the
Console to put all participants in exactly one subscription.** This lab deliberately
does not set `labsPerSubscription`, a default participant count, or a participant
limit. Omitting that field does not itself enforce a single subscription: check
the Console's reservation preview before starting.

The Console's selected regions and their order are authoritative. The
`preferredLocation` list in [lab-defaults.json](lab-defaults.json) only seeds the
Console defaults; the coach can remove, reorder or replace regions to respond
to subscription restrictions and capacity changes. Both hooks use exactly the
supplied list, not a hard-coded comparison with those defaults.

Each user receives one resource group with `Owner`, and only `Reader` on the
subscription. No additional resource group is created by these hooks. No Copilot
or Microsoft 365 licenses are requested. Cost fields are omitted; the documented
Console fallback is USD 25 per lab/day, an estimate rather than a spending limit.

The Console supplies authenticated Az PowerShell, an isolated Azure CLI profile,
and the `Update-MhhToken` / `New-MhhStablePassword` helpers. The hooks do not log
in, switch subscriptions, create users, or grant additional roles. They require
PowerShell 7, Azure CLI, `Az.Accounts`, and `Az.Resources`. The deployment is
self-contained: all runtime files must be imported from this `labautomation`
folder. It does not depend on sibling repository directories or runtime downloads.
Both hooks check the six required VM files before any Azure calls and report an
incomplete content package explicitly.

The canonical deployment assets have been moved here, not copied:

- [template-linux.json](template-linux.json) and [parameters-linux.json](parameters-linux.json)
- [template-win2025.json](template-win2025.json) and [parameters-win2025.json](parameters-win2025.json)
- [reconfig-ubuntu.sh](reconfig-ubuntu.sh) and [reconfig-win.ps1](reconfig-win.ps1)

Re-import the complete folder after updating the Console content. Importing only
the hook scripts is insufficient.

Both hooks verify the Az PowerShell subscription and the active isolated CLI
subscription before proceeding. Account-context queries use that verified current
context without `--subscription` (`az account list-locations` does not accept it);
resource commands explicitly include the target subscription.

## What is deployed

Per participant, into their existing resource group:

| VM | Image from the existing template | SKU |
| --- | --- | --- |
| `vm-linux-mh` | Ubuntu Server 20.04 LTS Gen2 | `Standard_D2ads_v5` |
| `vm-win2025-mh` | Windows Server 2025 Datacenter Gen2 | `Standard_D4ads_v5` |

Windows Server 2012 R2 is **not** deployed because no usable image is currently
provided for this automation. Challenge 6 therefore needs a separately supplied
server, or is skipped. Arc onboarding and the challenge resources remain
participant exercises.

The existing ARM templates, parameter files, public IPs, disks and networking are
reused. SSH (22), RDP (3389), and Windows WinRM (5985) retain their existing public
inbound rules. This is a disposable training environment, not a production
network design. Do not put sensitive data on these VMs.

The baseline is [create_vms.sh](../resources/demo-vm-creator/create_vms.sh), not
the older PowerShell creator. The existing ARM templates, parameter files and
guest scripts were moved here without changing their contents. The Bash creator
now resolves these shared files relative to its own location; its VM creation,
region/SKU distribution and asynchronous reconfiguration logic are unchanged.
Its separate Windows Server 2012 R2 template and parameters remain in the
standalone creator directory and are not part of this Console deployment.

## Shared stage and region mapping

[shared-deploy-lab.ps1](shared-deploy-lab.ps1) runs before the participant fan-out:

1. Normalize and sort all supplied user object IDs.
2. Validate the Console-supplied programmatic region names against the
   subscription's Azure region catalog, rejecting empty, duplicate or unknown
   names. Assign one region per user using `index % regionCount` in the supplied
   order. The initial defaults come from [lab-defaults.json](lab-defaults.json);
   they are not an allowlist.
3. Register required compute, network, Arc and challenge resource providers and
   wait for registration to finish.
4. Verify the subscription's SKU location restrictions and available regional,
   VM-family, VM-count and public-IP quotas for the whole planned deployment.
   Both SKUs currently consume the same VM-family quota: **6 vCPUs per user**.
   Existing compatible VMs with the expected lab names, including unmarked VMs
   eligible for the approved reuse policy below, are not counted as new VM/core
   demand.
   Public IP limits and current usage come from `az network list-usages`: both
   the overall `PublicIPAddresses` counter and the
   `IPv4StandardSkuPublicIpAddresses` counter must have capacity. These names were
   confirmed by the Console deployment's actual diagnostic response. Basic and
   IPv6 quotas are not applied to the Standard IPv4 addresses created here.
   Missing/duplicate counters, invalid values and failed API calls stop the
   deployment explicitly. No `Microsoft.Quota` registration or REST calls are
   needed. Existing public IPs, including partially deployed VM resources, are
   not counted as new IP demand.
5. Save the user-to-region mapping as outputs of the subscription ARM deployment
   `microhack-arc-server-placement`, containing **no Azure resources**.
   Re-runs retain the existing deployment record's metadata location, even when
   the Console selects a different first VM region. This does not affect where
   participant VMs are deployed.
   The template is serialized to a unique temporary JSON file and passed through
   `-TemplateFile`, avoiding Az.Resources dynamic-parameter serialization of
   nested PowerShell objects. The file contains only placement metadata, no
   credentials, and is removed in `finally` on success or failure.

The user RGs and their direct `Owner` assignments must already exist, as
guaranteed by the Console. The shared stage checks these assignments to account
for existing participant VMs during quota validation. Ambiguous ownership,
missing quota information, unavailable/restricted SKUs or insufficient quotas
fail explicitly. No quotas are raised and no alternate SKU or region is selected.
Provider registration is the only subscription preparation performed; Defender
plans, custom policies and service principals are not configured.

[deploy-lab.ps1](deploy-lab.ps1) reads the saved mapping and checks that the
supplied user owns the supplied resource group. Both VMs go into that user's
assigned region, regardless of the resource group's metadata location.

The default list of regions and the two SKUs match the verified Bash script; the
offline tests detect default drift and verify Console overrides. A recognized
Azure region name does not guarantee that its SKUs are accessible in a particular
subscription. Availability is subscription-specific and cannot be proven offline.
The preflight does not reserve quota or guarantee live regional capacity, image
availability, or exemption from Azure Policy.

## Credentials and asynchronous reconfiguration

The local account is `mhadmin`. `New-MhhStablePassword -Purpose vm-admin` provides
a stable, lab-scoped password for both VMs. The `TemplateParameterObject`
contains its string value in memory so Az.Resources can serialize it; a
PowerShell `SecureString` object in that hashtable can fail serialization.
Both ARM templates retain the `secureString` parameter type, which prevents ARM
from recording the password value in deployment history. No password file or
password CLI argument is created. Credentials
and public IPs are emitted only after both VMs have deployed and both
reconfiguration requests have been accepted.

Reconfiguration deliberately matches the Bash mechanism:

- Linux: action Run Command with `--no-wait`, using `reconfig-ubuntu.sh`.
- Windows: managed Run Command with asynchronous execution, using
  `reconfig-win.ps1`.

**Acceptance is not completion.** The guest scripts stop the Azure guest agent;
Windows also reboots. The dashboard therefore reports
`Submitted asynchronously - completion NOT verified`, never "Arc-ready".
Before onboarding, connect through SSH/RDP and verify:

- Linux: the Azure Linux agent is stopped and the outbound IMDS block exists
  (`sudo ufw status verbose`).
- Windows: `WindowsAzureGuestAgent` is stopped/disabled, the `BlockAzureIMDS`
  firewall rule is enabled, and machine-level `MSFT_ARC_TEST` is `true`.
- Windows has completed its reboot and both servers remain accessible.

No guest-completion polling or automatic Arc onboarding is performed.

## Re-runs and recovery

- The same participant list and ordered region list produce the same region
  mapping, VM names and passwords. Participant input ordering does not matter;
  region ordering deliberately does.
- Successfully provisioned VMs are reused when their region and size match and
  their `microhackArcUserId` tag matches or is absent/empty. Under the explicitly
  approved permanent recovery policy, missing ownership tags are automatically
  set without manual origin/credential verification, but only for `vm-linux-mh`
  and `vm-win2025-mh` in the Console-provided participant-owned RG. The shared
  preflight permits these unmarked VMs; the participant hook tags and reuses them
  with an explicit warning. Conflicting nonempty owner tags are never overwritten.
- All ownership and reconfiguration tag writes use `az tag update --operation
  Merge`, which initializes missing tags and preserves unrelated tags. VM data
  is read again after ownership tagging; the tag API response is not a VM object.
- `microhackReconfiguration=submitted` prevents submitting the scripts again to
  a guest whose Azure agent may already be disabled. It records submission,
  **not** verified success.
- A `submitting` tag means the process failed or was interrupted around request
  submission. The next run fails instead of guessing whether it is safe to retry.
  A coach must inspect the guest and Run Command state before changing this tag.
  If the original request was accepted, mark it `submitted`; clear it for retry
  only if the request was not accepted and the guest agent is still available.
- A VM creation interrupted before ownership tagging can therefore be retried
  without recreating that VM. Existing passwords are neither verified nor reset:
  if a reused VM did not originate from this lab's stable password, the dashboard
  password may not match it.
- An existing failed VM deployment is not silently treated as a healthy VM.
- Removing users or changing their assigned region first triggers a read-only
  subscription resource inventory. A stale mapping can be replaced if the entire
  subscription contains no resources other than resource groups and deployment
  metadata, plus the single explicitly approved governance workspace below.
  This supports retrying a failed deployment that saved the mapping
  but never created VMs. The coach sees an explicit warning when this happens.
- The sole workspace exception is the full ARM ID
  `/subscriptions/06dd34f3-80d4-42a0-ac31-446add752cd8/resourceGroups/McapsGovernance/providers/Microsoft.OperationalInsights/workspaces/mcaps42a0ac31446add752cd8-la`
  with type `Microsoft.OperationalInsights/workspaces`. ARM ID comparison is
  case-insensitive. This workspace is left untouched; no other workspace,
  subscription or resource in `McapsGovernance` is exempt.
- If any other resource exists (including partial networks, disks or unrelated
  resources), changed assignments still fail before VM deployment. No resources
  are deleted, moved or adopted during replanning; the previous placement remains
  intact. Invalid or failed inventory responses cannot authorize a replan. Restore the previous
  participant/region lists or have the coach inspect and clean up through the
  normal Console/event lifecycle.

The hooks do not delete resources or perform automatic cleanup.

## Participant exercises and coach duties

Use the Console-provided resource group in **all** challenges and walkthroughs;
replace example names such as `mh-arc-servers-rg` with that group. Do not create a
second group. RG-scoped resource creation, role assignments and policy assignments
remain participant tasks.

The coach handles operations requiring permissions beyond RG `Owner`:

- Create an Entra application/service principal for each user when needed for
  onboarding, and arrange secure delivery of its credentials. The onboarding role
  must be scoped to that user's RG, not the subscription.
- Confirm resource provider registration (automated by the shared hook).
- Enable/configure subscription-wide Defender for Servers plans and related
  shared settings for challenge 4, with explicit awareness of the charges.
- Publish any custom policy definitions at subscription or management-group scope
  for challenge 7; participants assign them only to their own RG.

## Offline validation

No Azure session, installed Az modules or Pester installation is needed:

```powershell
pwsh -NoProfile -File .\tests\offline.Tests.ps1
```

The tests replace Azure commands and Hackbox helpers with in-process mocks. They
check PowerShell parsing, configuration/Bash parity, the real template parameter
sets, placement, quota thresholds, credentials, asynchronous commands, failure
propagation and re-runs. They do **not** validate an actual Azure deployment.
They also deploy from an isolated copy of only the runtime `labautomation`
files, without the original repository layout, and test that each missing asset
fails before Azure access.
The [network quota fixture](tests/fixtures/network-usages.json) uses the counter
names, labels and string values observed in the Console diagnostics, restored to
the CLI's unprojected `name` / `currentValue` / `limit` response shape.

No real Azure test is authorized for this implementation. If one is approved
later, local execution needs explicit Az PowerShell **and** Azure CLI login,
the correct subscription in both contexts, Hackbox helper implementations, and
Console-equivalent RGs and RBAC. Run the shared hook first and the participant
hook second; do not add interactive login to either platform hook.
