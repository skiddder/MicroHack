# Walkthrough Challenge 2 - Azure Monitor, Update Manager, Change Tracking and Inventory

[Previous Challenge Solution](../challenge-01/solution-01.md) - **[Home](../../Readme.md)** - [Next Challenge Solution](../challenge-03/solution-03.md)

Documentation checked against Microsoft Learn on **2026-11-03**.
Allow additional time for policy evaluation, initial data ingestion and patching/reboots.

## Prerequisites and scope

- Complete [Challenge 1](../../challenges/challenge-01.md). Both servers must appear as **Connected** under **Azure Arc > Machines**, with their system-assigned managed identities enabled.
- Use the **Arc machine resources** (`Microsoft.HybridCompute/machines`), not the underlying Azure IaaS VMs used to simulate on-premises servers. Their Azure VM guest agents were deliberately disabled; do not re-enable them or remove the IMDS block.
- In the Hackbox Console, keep everything in your existing participant RG and subscription. You have RG `Owner`, not subscription `Owner`. Keep **`SecurityControl=Ignore`** on the RG. Provider registration, subscription-wide policy and permissions outside your RG are coach tasks.
- Verify the [AMA supported operating systems](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-supported-operating-systems), [Change Tracking support matrix](https://learn.microsoft.com/en-us/azure/azure-change-tracking-inventory/change-tracking-inventory-support-matrix) and service availability for your assigned region.
- Allow the documented outbound connections for [AMA](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-network-configuration), Azure Arc and your OS update sources. This exercise does not require opening additional public inbound ports.
- Ask the coach to approve service costs and update/reboot timing. Do not activate Windows Server benefits, paid plans or licenses merely to make a portal blade appear.

### These are separate services

| Capability | Required components |
| --- | --- |
| Windows event logs / Linux Syslog | Azure Monitor Agent (AMA), log DCRs, DCR associations, Log Analytics workspace |
| Classic VM insights performance | AMA, a **VM insights-specific** DCR and association, Log Analytics workspace |
| Change Tracking and Inventory | AMA, Change Tracking extension, a **Change Tracking-specific** DCR and association, Log Analytics workspace |
| Azure Update Manager | Connected Arc machine, Update Manager extensions and access to OS update sources; **no AMA, Log Analytics workspace or Automation account dependency** |

Do not install the retired Log Analytics agent (MMA/OMS) or use Automation Update Management.
The [current Update Manager overview](https://learn.microsoft.com/en-us/azure/update-manager/overview) explains the independent update-management architecture.

## Task 1: Create or select your Log Analytics workspace

1. In the [Azure portal](https://portal.azure.com/), search for **Log Analytics workspaces** and select **Create**, or reuse your workspace from an earlier attempt.
2. Select your event subscription and **existing participant RG**. Use a name such as `mh-arc-servers-automation-law`.
3. Choose a workspace region. (Where you store logs and metrics is independant of where the meta data of your arc machines is stored. You can choose any region - i.e. the one closest to your onprem VMs.)
4. Review the settings, create the workspace and record its **resource ID** and **region**.

Keep the workspace, DCRs and Arc machines in your own RG for this lab so the policy assignment identity can be granted permissions at that scope.
For log collection, a DCR's region must match its destination workspace's region; it is not determined by the RG's metadata location.

References: [Create a Log Analytics workspace](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/quick-create-workspace), [DCR permissions and regional requirements](https://learn.microsoft.com/en-us/azure/azure-monitor/data-collection/data-collection-rule-create-edit).

## Task 2: Collect Windows events and Linux Syslog

Use **Monitor > Data Collection Rules > Create**, rather than the old workspace **Agents** navigation.
The portal has default and classic DCR creation experiences; the labels differ. Follow the [current DCR creation instructions](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/data-collection).

Create separate log DCRs to make their purpose and OS scope explicit:

| Setting | Windows | Linux |
| --- | --- | --- |
| Rule name | `mh-dcr-windows-events` | `mh-dcr-linux-syslog` |
| RG | Your participant RG | Your participant RG |
| Region | Workspace region from Task 1 | Workspace region from Task 1 |
| Resources | Your **Windows Arc machine** | Your **Linux Arc machine** |
| Data source | Windows Event Logs | Linux Syslog |
| Destination | Azure Monitor Logs: Task 1 workspace | Azure Monitor Logs: Task 1 workspace |

1. On **Basics**, select the telemetry type that supports the required guest log source. Use **Help me choose** in the default experience. Do not select platform-metrics export. In the classic experience, select platform **Windows** or **Linux**, respectively.
2. On **Resources**, add the corresponding **Machines - Azure Arc** resource. This creates the DCR association. The portal's agent-based onboarding installs AMA if needed; retain the Arc machine's system-assigned identity.
3. Under **Collect and deliver**, add the data source and the destination workspace.
   - **Windows Event Logs:** collect **Application** and **System** events, including **Information** for the test below, as well as Warning/Error/Critical as appropriate. Do not collect every channel or enable Security collection indiscriminately.
   - **Linux Syslog:** enable the **user** facility at minimum level **Information** so the `user.notice` test below is included. Select other facilities only if required. Do not rely on an unreviewed "all facilities" default.
4. Create each rule. Under the DCR's **Resources**, confirm the correct Arc machine is associated.
5. On each Arc machine, open **Extensions** and confirm `AzureMonitorWindowsAgent` or `AzureMonitorLinuxAgent` is provisioned successfully. An installed agent without a DCR association does not establish the requested collection.

*Please note:* An Arc machine can have several DCR associations. Keep these log rules separate from the VM insights and Change Tracking rules below to avoid duplicate ingestion or overwriting specialized configurations.
For public-endpoint collection of these sources, a separate DCE is not required merely because the machine is Arc-enabled; private-link designs have additional requirements.

References: [Windows event collection](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/data-collection-windows-events), [Syslog collection](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/data-collection-syslog), [Install and manage AMA](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-manage).

### Verify actual ingestion

#### Recommended: generate the events through Azure Arc Run Command

Use [Run Command for Arc-enabled servers](https://learn.microsoft.com/en-us/azure/azure-arc/servers/run-command) to demonstrate cloud-based administration without an interactive SSH/RDP session or guest credentials.
Azure RBAC authorizes the operation; the Connected Machine agent executes the script inside the guest.
This generates log records for AMA to collect normally; it does not force an ingestion flush.

**Prerequisites:** both Arc machines must be connected and use Connected Machine agent **1.33 or later**. Run Command must not be blocked by the agent's extension allow/block list.
Your participant RG `Owner` role includes `Microsoft.HybridCompute/machines/runCommands/write`; with a restricted role, ask the coach to verify that permission.
Run Command for Arc is currently **preview** and has **no dedicated Azure portal blade**. Do not use the underlying Azure VM's Run Command.

1. In the Azure portal, open **Cloud Shell** and select **Bash**. Use an existing Cloud Shell environment or a session without storage; do not create an additional lab RG just for shell storage.
2. Use Azure CLI **2.75.0 or later** (`az version`). The `connectedmachine` CLI extension installs automatically on first use; accept the installation prompt if shown.
3. Replace the placeholders below with your event subscription, participant RG and the two **Arc resource names** shown under **Azure Arc > Machines**. These are not necessarily the simulated Azure VM names.
4. Read each Arc resource's metadata location on its **Overview** page and enter it below. This is not the Log Analytics workspace location or necessarily the simulated VM's physical region.
5. Run the following in Cloud Shell, not in either guest. If a CLI command fails, resolve the error before continuing.

```bash
subscriptionId="<event-subscription-id>"
resourceGroup="<your-participant-rg>"
windowsMachine="<windows-arc-resource-name>"
linuxMachine="<linux-arc-resource-name>"
windowsArcLocation="<windows-arc-resource-location>"
linuxArcLocation="<linux-arc-resource-location>"

runSuffix=$(date -u +%Y%m%d%H%M%S)
windowsRunName="mh-ama-windows-$runSuffix"
linuxRunName="mh-ama-linux-$runSuffix"

az connectedmachine run-command create \
  --subscription "$subscriptionId" --resource-group "$resourceGroup" \
  --machine-name "$windowsMachine" --location "$windowsArcLocation" \
  --name "$windowsRunName" \
  --script 'eventcreate /T INFORMATION /ID 100 /L APPLICATION /SO MicroHack /D "MicroHack AMA Windows test"; exit $LASTEXITCODE'

az connectedmachine run-command create \
  --subscription "$subscriptionId" --resource-group "$resourceGroup" \
  --machine-name "$linuxMachine" --location "$linuxArcLocation" \
  --name "$linuxRunName" \
  --script 'logger -p user.notice -t MicroHack "MicroHack AMA Linux test"'

az connectedmachine run-command show \
  --subscription "$subscriptionId" --resource-group "$resourceGroup" \
  --machine-name "$windowsMachine" --name "$windowsRunName" \
  --query '{provisioningState:provisioningState,execution:instanceView}' --output json

az connectedmachine run-command show \
  --subscription "$subscriptionId" --resource-group "$resourceGroup" \
  --machine-name "$linuxMachine" --name "$linuxRunName" \
  --query '{provisioningState:provisioningState,execution:instanceView}' --output json
```

Check that each command's `instanceView` reports execution state **Succeeded** and exit code **0**, and inspect its output/error.
If execution is still in progress, repeat the corresponding `show` command. Resource provisioning success alone is not proof that the guest command succeeded.
The timestamped names create distinct executions when you repeat the test and remain within Linux's 36-character Run Command name limit.
No storage account, script upload or guest password is needed for these inline scripts.

Open the Arc machine's **Activity log** to inspect the Run Command create/update operation and its caller.
This demonstrates Azure control-plane authorization and auditing while the guest remains reachable through Arc rather than a public administration port.
See the [current CLI reference](https://learn.microsoft.com/en-us/cli/azure/connectedmachine/run-command?view=azure-cli-latest) for command details.

#### Fallback: generate the same events in a guest session

If Run Command is unavailable or intentionally blocked, agree an alternative with the coach.
The following local commands generate the same records, but do not demonstrate the Arc-based administration path.

Windows, from an elevated guest terminal:

```powershell
eventcreate /T INFORMATION /ID 100 /L APPLICATION /SO MicroHack /D "MicroHack AMA Windows test"
```

Linux, from a guest terminal:

```bash
logger -p user.notice -t MicroHack "MicroHack AMA Linux test"
```

#### Verify the records in Log Analytics

Whichever method you used, open the workspace's **Logs**, select a suitable time range and run these queries separately:

```kusto
Heartbeat
| where TimeGenerated > ago(30m)
| summarize LastSeen = max(TimeGenerated) by Computer, _ResourceId
```

```kusto
Event
| where TimeGenerated > ago(30m)
| where Source == "MicroHack"
| project TimeGenerated, Computer, EventLog, EventID, RenderedDescription
```

```kusto
Syslog
| where TimeGenerated > ago(30m)
| where ProcessName == "MicroHack"
| project TimeGenerated, Computer, Facility, SeverityLevel, SyslogMessage
```

Initial ingestion is asynchronous. It can take several minutes until the logs become visible. A missing table before its first record or an empty result is **not** proof of success.
Check the selected workspace, DCR resources/destination, event filters, extension status and outbound connectivity before proceeding.

## Task 3: Enable classic VM insights and enforce it with Azure Policy

### Choose the monitoring experience deliberately

Microsoft now recommends [OpenTelemetry metrics-based monitoring](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/metrics-opentelemetry-guest) for new VM and Arc monitoring deployments.
It stores metrics in an **Azure Monitor workspace**, not the Log Analytics workspace used for this lab's logs.
Creating that workspace also creates a [managed resource group](https://learn.microsoft.com/en-us/azure/azure-monitor/metrics/azure-monitor-workspace-manage).

This MicroHack deliberately uses the still-supported **logs-based (classic)** VM insights experience to preserve the existing one-RG-per-participant setup and its Log Analytics/Policy learning goals.
Do not accept portal defaults that create additional workspaces or managed RGs outside your permissions.
A coach can arrange an OpenTelemetry alternative with an approved Azure Monitor workspace, access and governance tagging; it is not an implicit prerequisite of this walkthrough.

### Enable performance collection

1. Open your first server under **Azure Arc > Machines > Monitoring > Insights**. This now opens the machine's **Monitor** page.
2. Select **Configure**. Choose **logs-based metrics / classic**; deselect OpenTelemetry metrics for this lab-only path.
3. Select **Customize infrastructure monitoring** and explicitly select the **existing Log Analytics workspace** from Task 1. Do not accept a newly generated default workspace.
4. Create a **VM insights DCR** for the logs-based experience. Verify its workspace destination and region. Leave **process/dependency collection (Map)** disabled if that option is shown. Recommended alerts are not required for this exercise.
5. Review and enable monitoring. Record the generated VM insights DCR's resource ID. Repeat for the other Arc server, reusing the suitable VM insights DCR.

The VM insights rule collects `Microsoft-InsightsMetrics` using `\VmInsights\DetailedMetrics`.
The Windows Event/Syslog DCRs from Task 2 are **not substitutes** for this rule.
See [Monitor a hybrid machine with VM insights](https://learn.microsoft.com/en-us/azure/azure-arc/servers/tutorial-enable-vm-insights) and [monitoring DCR definitions](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vm-enable-monitoring).

### Assign the current AMA-based initiative

1. Open **Policy > Assignments > Assign initiative**.
2. Set the scope to **your participant RG**, not the shared subscription.
3. Select **Enable Azure Monitor for Hybrid VMs with AMA**, not a legacy MMA initiative or an Azure-VM-only initiative.
4. Under **Parameters**, show all parameters:
   - Set **VMI Data Collection Rule Resource Id** to the **VM insights DCR** created above, not an event/Syslog rule.
   - Set **Enable Processes and Dependencies** to **false**.
   - Keep the applicable deployment effects enabled.
5. Configure the assignment's **system-assigned managed identity** on the **Managed identity** tab (or corresponding identity section), and select its metadata location.
   This is the **policy remediation identity**, not the Arc machine identity or the onboarding service principal.
6. Review the initiative's required roles. Confirm the assignment identity has those roles at the scopes needed to deploy extensions and associate the DCR. Portal assignment can grant the roles when you have permission; if access is missing, ask the coach. Do not broaden the assignment to subscription scope.
7. Create the assignment. *Please note:* For the **existing** Arc machines the policy will not automatically remediate - only newly created arc machines in the assignment scope will automatically be configured. For exising VMs you need to create a remediation task if needed: Open **Policy > Remediation**, select the assignment and create remediation tasks for each applicable AMA installation and DCR-association `DeployIfNotExists` definition. Re-evaluate compliance when required.
8. Verify individual remediation results and extension/association state. Disabled Dependency Agent definitions do not need remediation.

Do **not** install Dependency Agent: [VM insights Map and Dependency Agent are deprecated and retire on 2028-06-30](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vminsights-maps-retirement).
Their retirement does not retire AMA or the classic performance view.

References: [VM insights initiatives and their parameters](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vminsights-enable-policy), [AMA policy identities and remediation](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-policy).

## Task 4: Assess and install updates with Azure Update Manager

Do not wait for AMA ingestion to enable Update Manager. Its own Arc extensions are installed automatically when you first trigger an update operation.
It uses Windows Update/WSUS or the configured Linux repositories; it does not supply updates or bypass OS support/subscription requirements.
For Ubuntu 20.04, check the configured repositories and any Ubuntu Pro/ESM requirements with the coach rather than assuming extended-support packages are available.

1. Open **Azure Update Manager > Machines** and filter to your subscription and RG. Select the **Arc-enabled** Windows and Linux machines.
2. Select **Check for updates** / **Assess now**. Wait for the assessment status and inspect failures rather than treating an empty update list as a successful assessment.
3. Enable periodic assessment using **Policy > Definitions**:
   - Definition: **Configure periodic checking for missing system updates on Azure Arc-enabled servers**.
   - Scope: your participant RG.
   - Parameters: **Assessment mode = AutomaticByPlatform** and **OS Type = Windows**.
   - Configure the remediation managed identity and required roles, then create a remediation task for the existing machine.
4. Create a second assignment with **OS Type = Linux** and remediate it as well. Periodic assessment checks approximately every 24 hours; it does **not** install updates.
5. Back in Update Manager, review missing updates. Select **One-time update** / **Install updates now** to install the approved OS updates, or create a maintenance schedule if the coach has agreed.
6. Review the selected machines, update selections, maintenance window and reboot settings before starting. Monitor **History** and individual installation results.
7. After any restart, confirm both Arc machines reconnect and run another assessment. Resolve failed/pending applicable OS updates before declaring the update task complete. Driver installation is not supported by Update Manager.

Do not use the Azure-VM patch-orchestration instructions for these Arc resources.
Do not register an Automation account or connect a Log Analytics workspace for Update Manager.

References: [Assess updates](https://learn.microsoft.com/en-us/azure/update-manager/view-updates), [periodic assessment policies for Arc](https://learn.microsoft.com/en-us/azure/update-manager/periodic-assessment-at-scale), [deploy updates and review results](https://learn.microsoft.com/en-us/azure/update-manager/deploy-updates), [prerequisites](https://learn.microsoft.com/en-us/azure/update-manager/prerequisites), [supported update types](https://learn.microsoft.com/en-us/azure/update-manager/support-matrix).

## Task 5: Enable Change Tracking and Inventory with AMA

Use the current **Change Tracking and Inventory** service, not an Automation-account-based onboarding workflow.
There is no step here to activate Windows Server Azure benefits. Licensing/benefit decisions belong to the coach and are not an agent-installation prerequisite in the current quickstart.

1. Open **Azure Arc > Machines**, select your Windows server and go to **Operations > Change tracking**.
2. Select **Enable change tracking and inventory feature with AMA**, then **Enable**. Follow the [current Arc quickstart](https://learn.microsoft.com/en-us/azure/azure-change-tracking-inventory/quickstart-monitor-changes-collect-inventory-azure-change-tracking-inventory).
3. Review any offered workspace settings and select your existing workspace. After deployment, inspect the generated Change Tracking DCR (typically `ct-dcr-...`), its destination and its association. Do not assume it reused the workspace from Task 1.
4. If the flow cannot select your required workspace, create a dedicated CTI DCR using the current [Change Tracking DCR template procedure](https://learn.microsoft.com/en-us/azure/azure-change-tracking-inventory/create-data-collection-rule), in your participant RG with the Task 1 workspace resource ID. Associate that rule with the Arc machine through **Monitor > Data Collection Rules > your CTI rule > Resources > Add**. Keep **only one CTI DCR association per machine**.
5. Confirm AMA and the **ChangeTracking-Windows** extension are installed successfully. The [current overview](https://learn.microsoft.com/en-us/azure/azure-change-tracking-inventory/overview-monitoring-agent) requires Change Tracking extension **2.20.0.0 or later**. Do not copy older extension-version examples from historical screenshots.
6. Repeat for Linux using its Arc resource and **ChangeTracking-Linux**, where supported.
7. In **Change Tracking and Inventory**, filter to your RG/machines and inspect **Inventory** / software data after initial collection. For policy-based rollout to further machines, use the built-in **Enable Change Tracking and Inventory for Arc-enabled virtual machines** initiative with the dedicated CTI DCR and remediate its applicable definitions.

Do not add Windows Event Logs or Syslog sources to a CTI DCR using the generic DCR editor; doing so can break Change Tracking. Use the separate rules from Task 2.
If an unexpected workspace or configuration outside your RG was created, ask the coach to resolve it; do not delete shared resources.

Verify the destination workspace directly:

```kusto
ConfigurationData
| where TimeGenerated > ago(24h)
| where ConfigDataType == "Software"
| summarize arg_max(TimeGenerated, *) by Computer, SoftwareName
| project TimeGenerated, Computer, SoftwareName, CurrentVersion, Publisher
```

Change events are stored in `ConfigurationChange`; current inventory is stored in `ConfigurationData`.
Initial inventory collection can take longer than a short portal refresh. Check the CTI extension, its DCR/association and workspace before concluding that there is no installed software.

References: [CTI overview and supported rollout methods](https://learn.microsoft.com/en-us/azure/azure-change-tracking-inventory/overview-monitoring-agent), [at-scale portal onboarding](https://learn.microsoft.com/en-us/azure/azure-change-tracking-inventory/enable-change-tracking-at-scale-machines-blade), [ConfigurationData schema](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/configurationdata).

## Task 6: Verify guest performance and completion

1. Return to each **Arc machine > Monitoring > Insights** / **Monitor**.
2. Select **Log based visualizations (Classic)** if a selector is shown. Inspect guest CPU, memory, disk and network charts. An empty chart immediately after onboarding is not a completed monitoring setup.
3. In the Task 1 workspace, verify the specialized performance stream:

```kusto
InsightsMetrics
| where TimeGenerated > ago(30m)
| summarize Samples = count(), LastSeen = max(TimeGenerated) by Computer, Namespace, Name
```

4. Confirm all of the following before completing the challenge:
   - Both Arc machines are connected and AMA is healthy.
   - Windows and Linux test messages appear in `Event` and `Syslog`.
   - The AMA-based monitoring initiative is assigned at your RG and applicable remediation succeeds.
   - Update Manager has successful assessments and reviewed update installation results; periodic assessment alone is not patching.
   - Software inventory is visible in the correct workspace and CTI view.
   - Both machines report guest performance data; Map/Dependency Agent is **not** a success criterion.

If data is missing, troubleshoot the relevant service's extension, DCR, association, identity and network path.
Waiting a fixed ten minutes is not a substitute for checking those results.
