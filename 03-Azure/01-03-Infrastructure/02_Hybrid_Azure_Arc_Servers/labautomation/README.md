# Hackbox automation: Azure Arc-enabled servers

## Console configuration

Import this MicroHack with `deploymentType = resourcegroup`. The Hackbox Console
controls both the participant count and subscription packing. **Configure the
Console to put all participants in exactly one subscription.** This lab deliberately
does not set `labsPerSubscription`, a default participant count, or a participant
limit. Omitting that field does not itself enforce a single subscription: check
the Console's reservation preview before starting.

Each user receives one resource group with `Owner`, and only `Reader` on the
subscription. No additional resource group is created by these hooks. No Copilot
or Microsoft 365 licenses are requested. Cost fields are omitted; the documented
Console fallback is USD 25 per lab/day, an estimate rather than a spending limit.

The Console supplies authenticated Az PowerShell, an isolated Azure CLI profile,
and the `Update-MhhToken` / `New-MhhStablePassword` helpers. The hooks do not log
in, switch subscriptions, create users, or grant additional roles. They require
PowerShell 7, Azure CLI, `Az.Accounts`, and `Az.Resources`. Keep the MicroHack's
directory layout intact: templates and reconfiguration scripts are loaded from
the sibling [VM creator directory](../resources/demo-vm-creator).

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
the older PowerShell creator. Neither creator nor the existing ARM templates or
guest scripts is modified by this integration.

## Shared stage and region mapping

[shared-deploy-lab.ps1](shared-deploy-lab.ps1) runs before the participant fan-out:

1. Normalize and sort all supplied user object IDs.
2. Assign one region per user using `index % regionCount`, in this exact order:
   `swedencentral`, `australiaeast`, `indiasouthcentral`, `westindia`, `westus2`.
3. Register required compute, network, Arc and challenge resource providers and
   wait for registration to finish.
4. Verify the subscription's SKU location restrictions and available regional,
   VM-family, VM-count and public-IP quotas for the whole planned deployment.
   Both SKUs currently consume the same VM-family quota: **6 vCPUs per user**.
   Existing automation-owned VMs are not counted as new VM/core demand.
5. Save the user-to-region mapping as outputs of the subscription ARM deployment
   `microhack-arc-server-placement`, containing **no Azure resources**.

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

The list of regions and the two SKUs match the verified Bash script; the offline
tests detect drift. Availability is subscription-specific and cannot be proven
offline. The preflight does not reserve quota or guarantee live regional capacity,
image availability, or exemption from Azure Policy.

## Credentials and asynchronous reconfiguration

The local account is `mhadmin`. `New-MhhStablePassword -Purpose vm-admin` provides
a stable, lab-scoped password for both VMs. The ARM deployment receives a
`SecureString`; no password file or password CLI argument is created. Credentials
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

- The same participant list produces the same region mapping, VM names and
  passwords. Input ordering does not matter.
- Successfully provisioned VMs are reused only when their region, size and
  `microhackArcUserId` tag match. Unmarked/conflicting VMs are not adopted.
- `microhackReconfiguration=submitted` prevents submitting the scripts again to
  a guest whose Azure agent may already be disabled. It records submission,
  **not** verified success.
- A `submitting` tag means the process failed or was interrupted around request
  submission. The next run fails instead of guessing whether it is safe to retry.
  A coach must inspect the guest and Run Command state before changing this tag.
  If the original request was accepted, mark it `submitted`; clear it for retry
  only if the request was not accepted and the guest agent is still available.
- A VM creation interrupted before its ownership tag is written also requires
  coach inspection of the deployment and credentials before it can be adopted.
- An existing failed VM deployment is not silently treated as a healthy VM.
- Removing users or changing their assigned region in an existing mapping fails
  before VM deployment. Keep the participant list stable for re-runs. For a new
  event, the coach must clean up the old event's resources and placement deployment
  through the normal Console/event lifecycle before starting again.

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

No real Azure test is authorized for this implementation. If one is approved
later, local execution needs explicit Az PowerShell **and** Azure CLI login,
the correct subscription in both contexts, Hackbox helper implementations, and
Console-equivalent RGs and RBAC. Run the shared hook first and the participant
hook second; do not add interactive login to either platform hook.
