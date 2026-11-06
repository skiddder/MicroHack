# Setup and Hackbox automation: Azure Arc-enabled servers

This directory is the central location for **all** environment and demo setup
files for this MicroHack. Add future setup assets here, not under `resources`.
The former `resources` contents were moved here, not copied.

| Setup area | Location |
| --- | --- |
| Hackbox Console hooks and shared VM assets | This directory |
| Standalone Bash and legacy PowerShell VM creators, including Windows Server 2012 R2 assets | [demo-vm-creator](demo-vm-creator/README.md) |
| Optional demo Arc onboarding and Ansible playbooks | [demo-vm-onboarder](demo-vm-onboarder/README.md) |
| Manual subscription preparation | [subscription-preparations](subscription-preparations) |
| Targeted Console RG-pair cleanup | [2-console-resource-groups.ps1](cleanup/2-console-resource-groups.ps1) |
| Legacy standalone bulk cleanup | [1-resource-groups.ps1](cleanup/1-resource-groups.ps1) |
| Change Tracking DCR template | [template-DCR-ChangeTracking.json](ChangeTracking/template-DCR-ChangeTracking.json) |
| Challenge 7 machine-configuration package | [AddKey.zip](AddKey.zip) |

Moving these tools does not make them Console deployment stages. The Console
only runs its existing hooks; manual/demo scripts retain their separate
authentication, prerequisites and behavior. In particular, the Console does not
run cleanup, request quota increases or perform demo Arc onboarding.

## Console configuration

Import this MicroHack with `deploymentType = resourcegroup-with-subscriptionowner`. The Hackbox Console
controls both the participant count and subscription packing. The
`labsPerSubscription` default is **10**; larger events use multiple subscriptions.
This is a packing default, not an event-wide participant limit. Check the
Console's reservation preview before starting, especially for existing events
whose saved settings may differ from the imported defaults.

The Console's selected regions and their order are authoritative. The
`preferredLocation` list in [lab-defaults.json](lab-defaults.json) only seeds the
Console defaults; the coach can remove, reorder or replace regions to respond
to subscription restrictions and capacity changes. Both hooks use exactly the
supplied list, not a hard-coded comparison with those defaults.

The default order is **Sweden Central, Australia East, West US 2**.
West India is excluded because the required VM quota is unavailable for this
event setup. Re-import the content to load the updated defaults, and check the
Console's selection: previously saved event selections are not automatically
rewritten by this repository change. Remove West India there before deployment.

Each user receives one resource group and **`Owner` on the shared subscription**,
provisioned by the Console. A direct RG `Owner` assignment is not required in
this mode; RG access is inherited from the subscription. This permits
RG creation, including service-managed RGs, and subscription-scope deployment
validation (`Microsoft.Resources/deployments/validate/action`) for Challenge 5.
**Participant RGs are not authorization boundaries:** every participant can
modify other participants' resources and subscription-level role assignments.
Use this only in the disposable event subscription and coordinate shared changes
with the coach. Subscription Owner does not grant Entra or management-group rights.

The participant hook accepts both this mode and the older `resourcegroup` mode
for compatibility. The older mode retains the Console's subscription `Reader`
permissions and does not provide the additional privileges required here.
Dedicated `subscription` deployments remain unsupported.
The hooks create one additional `-onprem` RG per participant; see the layout below. No Copilot
or Microsoft 365 licenses are requested. Cost fields are omitted; the documented
Console fallback is USD 25 per lab/day, an estimate rather than a spending limit.

Every lab/demo resource group must carry **`SecurityControl=Ignore`** so MCAPS
Governance does not disable the training environment's public-IP access. The
shared hook merges this tag into the Console-provisioned Azure RGs and creates
the on-prem RGs with the tag already present when direct RG ownership or a
previously tagged Azure RG plus subscription Owner is visible. Otherwise,
this preparation is deferred to the participant hook, which
always confirms both groups before VM creation. Tag API failures or
missing confirmation stop the deployment. Only participant RGs are tagged, not
the `McapsGovernance` RG or unrelated subscription groups.

Standalone Bash/PowerShell creators and the demo onboarder set this tag when
creating RGs and use Merge for existing target RGs, preserving other tags. For
manual RG creation, add it on the portal's Tags tab before creating resources.
This is a lab-specific governance exception, not a production recommendation.
It does not automatically restore NSG rules or public-IP access already changed
by Governance; that requires inspecting the existing network configuration.

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

### Personalized challenge and solution text

The Hackbox Console resolves `secret` elements in normal Markdown text using
the current participant's credentials. Specify the exact `group` and `name`
attributes and an explicit closing tag. See the
[Challenge 1 resource group reference](../challenges/challenge-01.md#actions).
Use group `Azure` for platform labels such as `Subscription ID` and
`Entra ID Username`, and `Lab-Deployment` for this hook's credential labels:
`Azure exercise resource group`, `Simulated on-prem resource group`,
`VM Admin Username`, `VM Admin Password`, `vm-linux-mh` and `vm-win2025-mh`.
The two VM labels contain public IP addresses, not Arc resource names.

Use `show="always"` for non-sensitive names, IDs and addresses; clicking copies
the value. Keep passwords initially masked with `show="false"`. Never put these
elements in inline code or fenced code blocks: copy the resolved values from
the surrounding text into script placeholders instead.

Missing credentials render as `undefined`. Re-import the updated challenge,
solution and deployment content and verify the labels in a participant session.
The tags only resolve in the Console; when reading the Markdown elsewhere or
using standalone setup, use your own environment values. Resources created
during the exercises (workspaces, Key Vaults, DCRs and storage accounts) are not
emitted by this hook, so their names must be recorded by the participant rather
than referenced through invented credential labels.

### Re-import and verify the new event

1. Re-import the complete `labautomation` content and create a **new event**.
   Verify that the Console selects `resourcegroup-with-subscriptionowner` and
   uses **10 labs per subscription** and the preferred region order
   `swedencentral, australiaeast, westus2`.
2. After provisioning, check **Access control (IAM)** for a participant:
   subscription `Owner` must be present. RG access may be inherited; a second
   direct RG assignment is not necessary. The hook checks subscription Owner
   and validates the Console-supplied user/RG pair against existing ownership
   tags before deploying VMs. It does not assign or repair roles.
3. Use a participant session, allowing for RBAC propagation and refreshing the
   session if necessary. Verify creation of a uniquely named empty test RG with
   `SecurityControl=Ignore`, then delete only that test RG.
4. Confirm the dashboard shows **Azure exercise resource group** and
   **Simulated on-prem resource group**. The first is the unchanged Console RG,
   the second is `<Console-RG>-onprem`. Both must have `SecurityControl=Ignore`;
   only the second contains the two prepared Azure VMs and their infrastructure.
5. Onboard both servers' **Arc resources into the Azure exercise RG** in
   Challenge 1, then verify subscription-scope deployment validation in Challenge 5 with the
   participant account, not the coach or deployment service principal.

These are live Console acceptance checks, not guarantees provided by offline
tests. The new mode does not automatically tag additional service-managed RGs
or bypass Azure Policy/deny assignments. Coordinate their governance handling
with the coach before using features that create them.
[Challenge 2](../walkthrough/challenge-02/solution-02.md) uses OpenTelemetry guest
metrics in an Azure Monitor workspace: Windows is enabled manually and Linux
through generic AMA/DCR-association policies. Logs and Change Tracking retain
their Log Analytics workspace. Participants create the metrics workspace and
identify/tag its service-managed RG during the exercise, not in the hooks.

Both hooks verify the Az PowerShell subscription and the active isolated CLI
subscription before proceeding. Account-context queries use that verified current
context without `--subscription` (`az account list-locations` does not accept it);
resource commands explicitly include the target subscription.

## What is deployed

### Two resource groups per participant

This layout is for **new Console events only**. The Console-provided name is
kept unchanged; no Console naming customization or RG rename is required.

| Purpose | Example | Contents |
| --- | --- | --- |
| Azure exercise RG, provisioned by Console | `rg-labuser-0001` | Participant-created Arc machine representations, workspaces, DCRs, policies, Key Vault and other exercise resources |
| Simulated on-prem RG, provisioned by the hooks | `rg-labuser-0001-onprem` | Underlying Azure VMs, networks, disks, public IPs and their VM Run Commands |

The base name must leave room for the seven-character `-onprem` suffix within
Azure's 90-character RG name limit. Overlong names fail explicitly, without
truncation. There is deliberately no separate `-az` suffix on the Console RG.
The hooks tag both groups with `microhackArcUserId` and
`microhackArcPurpose=azure|onprem`; the on-prem group additionally records
`microhackArcAzureResourceGroup=<Console-RG>`. Existing same-name on-prem groups
must already have matching ownership/purpose/parent tags or deployment stops.
Unrelated tags are preserved.

No extra direct Owner role is added to the on-prem RG: participants inherit
access from subscription Owner. Tagged on-prem groups are excluded when the
shared preflight identifies the Console RG by direct Owner assignment, or by
matching `microhackArcPurpose=azure` and `microhackArcUserId` tags when the user
has subscription Owner. If neither association is visible, it reserves the
full demand without inferring a group name or changing any groups. The
participant hook trusts the Console-supplied user/RG pair, verifies subscription
Owner, checks that the RG exists, and rejects conflicting participant/purpose
tags before any writes. Unmarked Console RGs are initialized with the ownership
tags. The older `resourcegroup` mode still requires direct RG Owner.
Multiple matching RGs remain an error in the shared stage.
This remains an organizational split, not an access boundary.
Challenge 2 creates an Azure Monitor workspace with another service-managed RG;
the two provisioned participant groups do not replace that managed RG. Follow
the walkthrough's governance tagging and the cleanup procedure below.
Standalone Bash/legacy PowerShell demos retain their existing layouts.

Per participant, the hooks deploy these VMs into the **on-prem RG**:

| VM | Image from the existing template | SKU |
| --- | --- | --- |
| `vm-linux-mh` | Ubuntu Server 24.04 LTS x64 Gen2 (non-Pro) | `Standard_D2ads_v5` |
| `vm-win2025-mh` | Windows Server 2025 Datacenter Gen2 | `Standard_D4ads_v5` |

Windows Server 2012 R2 is **not** deployed because no usable image is currently
provided for this automation. Challenge 6 therefore needs a separately supplied
server, or is skipped. Arc onboarding and the challenge resources remain
participant exercises.

The shared Linux template uses `Canonical:ubuntu-24_04-lts:server:latest`,
the [official standard Ubuntu Server x64 Gen2 image](https://ubuntu.com/azure/docs/azure-how-to/instances/find-ubuntu-images/).
Ubuntu 24.04 is in standard security maintenance, so the Update Manager exercise
does not require Ubuntu Pro/ESM for standard OS security updates.

**Existing environments:** there is no migration from the old single-RG layout.
If expected lab VMs are found in the Azure exercise RG, deployment fails rather
than moving or duplicating them. Create a new event. Within the new two-RG layout,
compatible existing VMs in the tagged on-prem RG are reused; image changes affect
new VMs only, not existing OS disks.

The existing ARM templates, parameter files, public IPs, disks and networking are
reused. SSH (22), RDP (3389), and Windows WinRM (5985) retain their existing public
inbound rules. This is a disposable training environment, not a production
network design. Do not put sensitive data on these VMs.

The baseline is [create_vms.sh](demo-vm-creator/create_vms.sh), not
the older PowerShell creator. ARM templates, parameter files and guest scripts
are shared from this directory, including the Ubuntu 24.04 image selection. The Bash creator
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
   When a verified RG association is visible, the Console Azure RG is tagged and its
   matching on-prem RG is created/reused with `SecurityControl=Ignore` before
   VM/core demand is validated. An empty
   tagged on-prem RG can therefore remain if a later quota/SKU check fails.
   Existing VMs and IPs are checked in the on-prem RG; incompatible VMs still
   fail validation.
   If no direct or previously tagged RG association is visible, the
   shared stage warns and counts both VMs (6 vCPUs) and both public IPs as new
   demand. It does not derive RG names from usernames. Existing resources can
   be discounted on subsequent runs using the participant hook's matching Azure
   RG tags and verified subscription Owner, even without direct RG assignments.
   Failed Azure API calls are still fatal.
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

The Console Azure RGs and participant RBAC must exist before the participant
hook runs. The shared stage uses direct assignments or existing Azure RG tags
with subscription Owner to identify each corresponding on-prem RG during quota
validation; otherwise it defers RG preparation. Ambiguous ownership,
missing quota information, unavailable/restricted SKUs or insufficient quotas
fail explicitly. No quotas are raised and no alternate SKU or region is selected.
Beyond the paired RG creation/tagging, provider registration is the only
subscription preparation performed; Defender plans, custom policies and service
principals are not configured.

[deploy-lab.ps1](deploy-lab.ps1) reads the saved mapping and checks that the
supplied user has subscription Owner in the default mode, or direct RG Owner
in the legacy mode. Existing contradictory Azure RG ownership/purpose tags
are rejected, not overwritten. It validates/reuses
the matching tagged on-prem RG and deploys both VMs there, in that user's assigned
region regardless of either resource group's metadata location.

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
and public IPs, plus the two RG names and their purpose, are emitted only after both VMs have deployed and both
reconfiguration requests have been accepted.

Both Console guests use managed Run Command with `--async-execution true`:

- Linux: `reconfigLinux`, using `reconfig-ubuntu.sh`.
- Windows: `reconfigWin`, using `reconfig-win.ps1`.

The CLI call waits for managed command provisioning, which must report
`Succeeded` before the VM tag is changed from `submitting` to `submitted`.
With asynchronous execution, provisioning completes when script execution starts,
not when it finishes. Unlike the former Linux action Run Command's client-side
`--no-wait`, this does not wait for the guest script's completion after it has
stopped the agent. See the [Run Command comparison](https://learn.microsoft.com/azure/virtual-machines/run-command-overview).
This intentionally differs from the standalone Bash demo creator, whose legacy
submission mechanism is unchanged.

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
  and `vm-win2025-mh` in the matching tagged on-prem RG. The shared
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
- For the known legacy action Run Command case, both hooks can reuse an
  `Updating` VM only when its name is an expected lab VM, its ownership tag
  exactly matches the participant (unmarked reuse does not qualify), and
  `microhackReconfiguration=submitted`. A live instance-view query must also
  report `ProvisioningState/updating`, `PowerState/running` and exactly one
  agent status, `ProvisioningState/Unavailable`. The enclosing on-prem RG,
  region and SKU must pass the usual checks.
  This is explicit degraded reuse, **not** a successful provisioning or
  guest-readiness verdict: a warning retains that distinction, as does the
  dashboard. The hook does not change the VM's Azure state, tags, password or
  Run Command, and it does not submit reconfiguration again. Verify both
  guests through SSH/RDP before onboarding; unrelated Azure VM updates can
  remain blocked while the agent is unavailable.
- VMs in `Creating` or `Updating` are polled with `az vm show` in both hooks
  before reuse unless the preceding detached-agent case qualifies, including
  after ownership tagging. There are at most 60 polls
  per check, ten seconds apart (about ten minutes plus Azure API time).
  Ownership, region and SKU are checked before waiting and on every response.
  Failed, canceled or unknown states and API errors stop immediately; a VM
  still busy at the limit also stops with a diagnostic. Inspect its Azure
  Activity Log and deployment/Run Command status before retrying. Waiting does
  not recreate VMs, clear reconfiguration tags or resubmit guest scripts.
  `submitting` and unknown reconfiguration tags stop immediately, including
  during the shared stage. Failed instance-view queries or malformed responses
  also stop rather than assuming that a guest was prepared.
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

## Cleaning up participant and linked managed resources

Do not assume the Console's normal teardown discovers an RG created by a content
hook. The coach must remove the paired groups explicitly, preferably **before**
Console teardown, using [2-console-resource-groups.ps1](cleanup/2-console-resource-groups.ps1).
Authenticate Az PowerShell to the event subscription first; the script never logs
in or switches subscriptions. Use the exact Console **Azure exercise RG names**:

```powershell
.\cleanup\2-console-resource-groups.ps1 `
    -SubscriptionId '<event-subscription-id>' `
    -AzureResourceGroupNames 'rg-labuser-0001', 'rg-labuser-0002' -WhatIf
```

Inspect the preview, then repeat without `-WhatIf` and confirm each deletion.
The script validates every requested pair, associated extra RG and workspace
reference before deleting any group. It deletes the on-prem group first, then
explicitly associated extra exercise RGs, then the Azure exercise group,
including **all contents**, regardless of who created each resource. It also
supports a remaining tagged on-prem RG after its Console RG was already removed.
Wildcards and a mismatched active subscription are rejected.

Additional participant-created RGs are included only with all these ownership tags:

| Tag | Value |
|---|---|
| `microhackArcPurpose` | `exercise` |
| `microhackArcAzureResourceGroup` | Exact Console Azure exercise RG name |
| `microhackArcUserId` | Same participant Entra object ID as the verified pair |

Set these tags when creating extra exercise RGs; neither a matching user ID
alone nor a name prefix establishes event ownership. Conflicting ownership on
an explicitly linked exercise RG stops cleanup. Do not apply these exercise
tags to service-managed RGs. As with all lab RGs, also set
`SecurityControl=Ignore`; that governance tag alone does not establish ownership.

For **Azure Monitor workspaces** (`Microsoft.Monitor/accounts`) inside the
verified deletion scopes, the script reads the actual default DCR/DCE resource
IDs from `properties.defaultIngestionSettings`. Both must reference one managed
RG in the selected subscription without conflicting ownership. It never
guesses associations from `MA_*` names or resource creator metadata.
[Azure automatically deletes the workspace's managed RG and its resources
when the workspace is deleted](https://learn.microsoft.com/en-us/azure/azure-monitor/metrics/azure-monitor-workspace-manage#delete-an-azure-monitor-workspace).
The script therefore deletes the owning exercise RG, **never the managed RG
directly**, then verifies disappearance with up to 60 checks, five seconds
apart. Remaining managed RGs produce an error requiring coach investigation;
there is no forced-deletion fallback. `-WhatIf` explains the indirect cleanup
but does not delete or wait. Declining the owning RG deletion does not trigger
managed cleanup verification.

Other groups, including governance, unselected participants and unlinked
managed RGs, remain untouched. Remaining RGs/resources outside the verified
scope are reported as objects with `Status=NotAssigned` and `ResourceId`.
This is **not** a claim that they were created by event participants. Review
them separately; other managed services are not automatically associated.
Run cleanup before Console teardown so the participant and workspace ownership
references are still available. Subscription-wide RBAC/policy definitions and
Entra objects are not comprehensively inventoried or cleaned by this RG script;
coordinate those separately with the Console/event lifecycle.

After an event, verify one tagged additional exercise RG and an Azure Monitor
workspace in the `-WhatIf` preview. After real cleanup, check that the extra RG
and workspace-linked managed RG disappeared while an untagged control RG
remained and was reported. This live acceptance check is not replaced by the
offline mock tests.
The legacy bulk cleanup script is not this paired Console cleanup path.

## Participant exercises and coach duties

Use the Console-provided **Azure exercise RG**, not the `-onprem` RG, for the participant resources in the
challenges and walkthroughs; replace example names such as `mh-arc-servers-rg`
with that group. Onboard the guests into it so Arc-scoped policies and monitoring
apply to their Arc representations. Reserve `-onprem` for the underlying VM
infrastructure and guest-preparation checks. Create further RGs only when an approved feature requires
them, and arrange `SecurityControl=Ignore` for those groups as well.
RG-scoped resource creation, role assignments and policy assignments remain
participant tasks. Although participants now have subscription Owner, coordinate
subscription-wide changes with the coach because they affect the whole event.

The coach handles directory/management-group access and coordinates shared settings:

- Create an Entra application/service principal for each user when needed for
  onboarding, and arrange secure delivery of its credentials. The onboarding role
  must be scoped to that user's RG, not the subscription.
- Confirm resource provider registration (automated by the shared hook).
- Enable/configure subscription-wide Defender for Servers plans and related
  shared settings for challenge 4, with explicit awareness of the charges.
- Coordinate custom policy definitions at subscription scope for challenge 7;
  participants can publish them with subscription Owner and assign them to their
  own RG. Publishing at management-group scope still requires separate permissions.

## Offline validation

No Azure session, installed Az modules or Pester installation is needed:

```powershell
pwsh -NoProfile -File .\tests\offline.Tests.ps1
```

The tests replace Azure commands and Hackbox helpers with in-process mocks. They
check PowerShell parsing, the subscription-owner default and both supported
RG deployment modes, configuration/Bash parity, the real template parameter
sets, placement, quota thresholds, credentials, asynchronous commands, failure
propagation and re-runs. They do **not** validate an actual Azure deployment.
They also deploy from an isolated copy of only the runtime `labautomation`
files, without the original repository layout, and test that each missing asset
fails before Azure access.
Two-RG creation/reuse, ownership conflicts, legacy-layout rejection, dashboard
RG names and targeted cleanup/WhatIf are covered with mocks.
The tests also cover the shared stage before Console RG/Owner visibility,
full quota accounting in that state, subscription-Owner-only deployments,
tag-based shared reruns, conflicting Azure RG tags and legacy direct ownership.
Detached-agent recovery is tested for both VM types and both hooks, including
zero new quota demand, unchanged VM state, no repeated Run Commands, and rejection
of missing/contradictory status data or submission tags. Both guests' managed
asynchronous command options and provisioning responses are checked with mocks.
The centralized legacy PowerShell creator's parameter sets are also checked
against its three local templates.

On Linux/WSL, validate the moved standalone demo paths with:

```bash
bash ./tests/setup-paths.Tests.sh
```

This syntax-checks the Bash scripts and runs the creator, onboarder and combined
entry point with mocked Azure CLI, jq and Ansible commands. It uses an isolated
copy with spaces in its path, starts outside the setup directory, and checks all
template, parameter, reconfiguration and playbook references. No cloud commands
are sent; only the temporary playbook copies are populated with dummy values.

The [network quota fixture](tests/fixtures/network-usages.json) uses the counter
names, labels and string values observed in the Console diagnostics, restored to
the CLI's unprojected `name` / `currentValue` / `limit` response shape.

No real Azure test is authorized for this implementation. If one is approved
later, local execution needs explicit Az PowerShell **and** Azure CLI login,
the correct subscription in both contexts, Hackbox helper implementations, and
Console-equivalent RGs and RBAC. Run the shared hook first and the participant
hook second; do not add interactive login to either platform hook.

### Troubleshooting missing Console RG ownership

In `resourcegroup-with-subscriptionowner` mode, the Console may assign Owner
only at subscription scope. This is sufficient and does not require a second
direct RG assignment. The initial shared run then warns and uses conservative
quota accounting until the participant hook initializes the Console-supplied
RG's tags. Subsequent shared runs recognize those tags with subscription Owner.

If an older imported hook reports `Subscription Owner alone does not satisfy
this check`, re-import the complete updated content and retry the failed
deployment with the updated script version, not an older imported snapshot.
No additional role assignments or RG migration are required. Verify that the
event actually uses `resourcegroup-with-subscriptionowner`. In the older
`resourcegroup` mode, a direct RG Owner assignment remains mandatory. Missing
subscription Owner in the new mode, contradictory ownership tags and failed
Azure API calls still stop deployment. The hooks never repair RBAC or
overwrite conflicting ownership tags.
