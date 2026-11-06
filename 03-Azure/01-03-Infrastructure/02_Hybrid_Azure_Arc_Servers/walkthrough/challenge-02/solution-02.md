# Walkthrough Challenge 2 - Azure Monitor, Update Manager, Change Tracking and Inventory

[Previous Challenge Solution](../challenge-01/solution-01.md) - **[Home](../../Readme.md)** - [Next Challenge Solution](../challenge-03/solution-03.md)

Duration: 40 minutes - Allow additional time for policy evaluation, initial data ingestion and patching/reboots.

## Prerequisites and scope

- Complete [Challenge 1](../../challenges/challenge-01.md). Both servers must appear as **Connected** under **Azure Arc > Machines**, with their system-assigned managed identities enabled.
- Use the **Arc machine resources** (`Microsoft.HybridCompute/machines`), not the underlying Azure IaaS VMs used to simulate on-premises servers. Their Azure VM guest agents were deliberately disabled; do not re-enable them or remove the IMDS block.
- In the Hackbox Console's default `resourcegroup-with-subscriptionowner` mode, you have `Owner` on your participant RG and the shared subscription. Use your participant RG for this walkthrough and keep **`SecurityControl=Ignore`** on it. Coordinate subscription-wide changes or additional managed RGs with the coach; do not modify other participants' resources. Entra and management-group permissions are separate.
- Here, **participant RG** means your **Azure exercise resource group** <secret group="Lab-Deployment" name="Azure exercise resource group" show="always"></secret>, containing your Arc representations and exercise resources. The prepared Azure VMs live separately in the **Simulated on-prem resource group** <secret group="Lab-Deployment" name="Simulated on-prem resource group" show="always"></secret>. Do not select that infrastructure RG for workspaces, DCRs, Arc Run Command or Arc policy assignments.
- Verify the [AMA supported operating systems](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-supported-operating-systems), [Change Tracking support matrix](https://learn.microsoft.com/en-us/azure/azure-change-tracking-inventory/change-tracking-inventory-support-matrix) and service availability for your assigned region.
- Allow the documented outbound connections for [AMA](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-network-configuration), Azure Arc and your OS update sources. This exercise does not require opening additional public inbound ports.
- Ask the coach to approve service costs and update/reboot timing. Do not activate Windows Server benefits, paid plans or licenses merely to make a portal blade appear.

### These are separate services

| Capability | Required components |
| --- | --- |
| Windows event logs / Linux Syslog | Azure Monitor Agent (AMA), log DCRs, DCR associations, Log Analytics workspace |
| OpenTelemetry guest performance metrics | AMA, an **OpenTelemetry performance** DCR and association, Azure Monitor workspace |
| Change Tracking and Inventory | AMA, Change Tracking extension, a **Change Tracking-specific** DCR and association, Log Analytics workspace |
| Azure Update Manager | Connected Arc machine, Update Manager extensions and access to OS update sources; **no AMA, Log Analytics workspace or Automation account dependency** |

Do not install the retired Log Analytics agent (MMA/OMS) or use Automation Update Management.
The [current Update Manager overview](https://learn.microsoft.com/en-us/azure/update-manager/overview) explains the independent update-management architecture.
Logs and Change Tracking remain in **Log Analytics** and use KQL. Guest performance metrics use **OpenTelemetry (OTel)**, an **Azure Monitor workspace** and PromQL.
AMA collects the guest metrics; you do not need to install a separate OpenTelemetry Collector or expose an inbound OTLP endpoint.

## Task 1: Create or select your Log Analytics workspace

1. In the [Azure portal](https://portal.azure.com/), search for **Log Analytics workspaces** and select **Create**, or reuse your workspace from an earlier attempt.
2. Select subscription <secret group="Azure" name="Subscription ID" show="always"></secret> and **existing participant RG** <secret group="Lab-Deployment" name="Azure exercise resource group" show="always"></secret>. Use the workspace name `mh-arc-servers-automation-law`.
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

*Please note:* An Arc machine can have several DCR associations. Keep these log rules separate from the OpenTelemetry performance and Change Tracking rules below to avoid duplicate ingestion or overwriting specialized configurations.
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

For the script below, set **subscriptionId** to <secret group="Azure" name="Subscription ID" show="always"></secret>
and **resourceGroup** to <secret group="Lab-Deployment" name="Azure exercise resource group" show="always"></secret>.
Copy these values into the quoted placeholders; Secret tags are not expanded inside code blocks.
Read the Arc machine names and locations from their portal resources as described above.

```bash
subscriptionId="<event-subscription-id>"
resourceGroup="<your-azure-exercise-rg-containing-the-arc-resources>"
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

## Task 3: Enable OpenTelemetry metrics manually on Windows and at scale on Linux

Use the [OpenTelemetry metrics-based experience](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/metrics-opentelemetry-guest), which Microsoft recommends for new VM and Arc monitoring deployments.
The first machine (**Windows**) is configured manually. The second machine (**Linux**) receives its monitoring configuration through Azure Policy.
Keep the Task 2 log DCRs and their Log Analytics destination unchanged.

### Create your Azure Monitor workspace

1. In **Subscriptions > your event subscription > Resource providers**, verify that **Microsoft.Monitor** is **Registered**. Register it if necessary and wait for registration to finish. **Microsoft.Insights** must also be registered.
2. Search for **Azure Monitor workspaces**, select **Create**, and choose your event subscription and **existing Azure exercise RG**, not the `-onprem` RG. This is a different resource type from Log Analytics.
3. Choose a workspace name unique to your participant within the shared subscription. Use your Azure exercise resource group name displayed above as a participant-specific suffix. Do not have every participant use the same name: the automatically generated managed RG name must also be distinct within the shared subscription.
4. Choose a service-supported workspace region agreed with the coach. Create the OTel DCR in this same region; it need not match the Arc machines' metadata locations or physical VM locations. This lab uses public endpoints; the metrics-based experience does not currently support Private Link.
5. Review and create the workspace. Record its full **resource ID**. Azure also creates a service-managed RG, normally `MA_<workspace-name>_<location>_managed`, containing its default ingestion DCR and DCE.
6. Open the workspace's **JSON View** and inspect `properties.defaultIngestionSettings`. Follow the referenced DCR/DCE resource IDs to identify the actual managed RG, rather than assuming ownership from its name. Record this RG and apply **`SecurityControl=Ignore`** to it as well. If naming/tag policies or a deny assignment prevent creation or tagging, stop and involve the coach; do not remove service-managed protections or modify another participant's managed RG.

Keep the workspace in your Azure exercise RG and leave its service-managed resources where Azure created them. Do not mark the managed RG as an additional `exercise` RG.
The managed ingestion DCR is **not** the guest-performance DCR used in the next steps.
The [coach cleanup procedure](../../labautomation/README.md#cleaning-up-participant-and-linked-managed-resources) discovers these workspace links and verifies Azure's automatic managed-RG deletion when the owning workspace is deleted.

Reference: [Create and manage an Azure Monitor workspace](https://learn.microsoft.com/en-us/azure/azure-monitor/metrics/azure-monitor-workspace-manage).

### Manually enable the first machine: Windows

1. Open your **Windows Arc resource** under **Azure Arc > Machines > Monitoring > Insights** / **Monitor**, then select **Configure**.
2. Keep **OpenTelemetry metrics** enabled and **deselect logs-based metrics / classic**. The Windows event and Linux Syslog rules from Task 2 remain active; this selection concerns performance collection only.
3. Select **Customize infrastructure monitoring** and explicitly choose the **Azure Monitor workspace you just created**. Do not accept a new default workspace or a destination belonging to another participant.
4. Keep the **default OpenTelemetry system metrics**. Disable **OpenTelemetry per-process metrics** and **recommended alerts** for this exercise. Default system metrics are collected at no additional cost; additional metrics, alerts and other services can incur charges. Do not create an Azure Managed Grafana workspace for this task.
5. Have the portal create a new **OpenTelemetry performance DCR** in your **Azure exercise RG**, in the Azure Monitor workspace's region. It is typically named `MSVMOtel-<region>-<name>`. Keep it separate from the Windows Event, Syslog and Change Tracking DCRs.
6. Review the selected resource, destination, RG and options, then select **Review + Enable > Enable**. Only enable the **Windows Arc machine** here. Do **not** manually enable performance monitoring on Linux.
7. Open **Monitor > Data Collection Rules > Resources**, locate the Windows Arc machine and inspect its new OTel rule. Copy the full **DCR resource ID** for the policy assignment below. Verify in its JSON definition:
   - `properties.dataSources.performanceCountersOTel` collects the `Microsoft-OtelPerfMetrics` stream.
   - `properties.destinations.monitoringAccounts[].accountResourceId` points to **your Azure Monitor workspace**.
   - `properties.dataFlows` sends that stream to the monitoring-account destination.
   - It contains only the intended cross-platform OTel performance configuration, not Windows-only event sources. The default OTel system metrics can be reused for Windows and Linux.
8. Confirm the Windows AMA extension is healthy and the OTel DCR's **Resources** lists Windows. Check for actual Windows metrics using Task 6 before considering this onboarding successful. Linux must not yet have this OTel DCR association.

Do not install a second monitoring agent or Dependency Agent. AMA from Task 2 can use multiple DCRs.
The default metrics include `system.uptime`, `system.cpu.time`, memory, disk and network metrics. They do **not** include every available counter; for example, `system.cpu.utilization` is an additional metric, so Task 6 derives CPU utilization from the default CPU-time metric.

References: [Portal monitoring configuration](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/tutorial-enable-monitoring), [OTel DCR definition and Arc associations](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vm-enable-monitoring), [default versus additional metrics](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/metrics-opentelemetry-guest-modify).

### Enable the second machine: Linux, with Azure Policy

**Important:** the [VM insights policy article](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vminsights-enable-policy) currently describes the **logs-based** experience and says dedicated metrics-based policies are not yet available. Do **not** use **Enable Azure Monitor for Hybrid VMs with AMA** as an OTel onboarding initiative.
Instead, use the following existing, generic **Arc Linux policies** to enforce AMA and associate the **already created OTel DCR**. They do not create an Azure Monitor workspace or generate an OTel rule.

| Purpose | Built-in policy definition | Definition ID |
| --- | --- | --- |
| Ensure AMA is installed | **Configure Linux Arc-enabled machines to run Azure Monitor Agent** | `845857af-0333-4c5d-bbbc-6076697da122` |
| Associate the OTel DCR | **Configure Linux Arc Machines to be associated with a Data Collection Rule or a Data Collection Endpoint** | `d5c37ce1-5f52-4523-b949-f19bf945b73a` |

1. Open **Policy > Definitions**, select the first **policy** above and choose **Assign policy**. Use **your Azure exercise RG** as the scope and an assignment name such as `mh-otel-linux-ama`. Do not select an Azure IaaS VM policy or scope the assignment to the shared subscription.
2. Set **Effect = DeployIfNotExists**. Configure a **system-assigned managed identity** for the assignment and select its metadata location. Review and grant the roles required by the definition at your RG. This is a **policy remediation identity**; the Linux Arc machine keeps its existing system-assigned identity.
3. Create a second assignment for the DCR-association policy, at the same RG scope, named for example `mh-otel-linux-dcr`. Show all parameters and set:
   - **Effect:** `DeployIfNotExists`.
   - **Data Collection Rule Resource Id or Data Collection Endpoint Resource Id** (`dcrResourceId`): the **OTel guest-performance DCR ID copied from Windows onboarding**.
   - **Resource Type** (`resourceType`): **`Microsoft.Insights/dataCollectionRules`**, not `Microsoft.Insights/dataCollectionEndpoints`.
4. Configure this assignment's own **system-assigned remediation identity** and grant the roles requested by the definition. The DCR and Arc machines are in the same participant RG, so do not broaden permissions to the subscription or managed RG. Confirm the grants actually succeeded; subscription Owner on your participant account is not a role grant to either remediation identity.
5. Create both assignments, then **wait for their first policy evaluations to finish**. In **Policy > Compliance**, open each assignment and refresh until resource-level results exist for the **Linux Arc resource**. Empty results or **Not started** are not a completed evaluation. If Linux is absent, check the RG scope, `osName` and whether its **Arc metadata location** is supported by the selected built-in definition.
6. Inspect the evaluated results. AMA should already be **Compliant** from Task 2; the missing OTel DCR association should be **Non-compliant**. Keep the original Syslog DCR association in place.
7. **Only after evaluation**, open **Policy > Remediation** and create a remediation task for the **non-compliant DCR-association assignment**, selecting the existing Linux Arc machine. If the AMA installation policy is also non-compliant, remediate it and wait for the extension to succeed as well. Do not create an empty remediation task before Linux has been evaluated.
8. Wait for successful remediation, inspect individual deployment results, then open the OTel DCR's **Resources** and confirm it now lists **both Windows and Linux Arc machines**. On Linux, verify AMA is healthy. Do not click **Configure/Enable** on Linux as a manual workaround; troubleshoot the assignment, remediation identity, DCR ID and association instead.
9. After another evaluation, confirm both Linux policies are compliant, then verify actual Linux metrics in Task 6. Compliance proves the configured resources exist, **not** that telemetry has arrived.

This is the at-scale pattern: configure the workspace and collection rule once, then use policy to enforce the agent and rule association for matching Linux Arc machines in scope.
New machines are configured through normal `DeployIfNotExists` processing; existing non-compliant machines need remediation. Neither evaluation nor ingestion is instantaneous.
The policies target Linux, so Windows retains its manually created association.

References: [AMA policy deployment and identities](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-policy), [Arc Linux AMA policy source](https://github.com/Azure/azure-policy/blob/master/built-in-policies/policyDefinitions/Monitoring/AzureMonitor_Agent_Linux_HybridVM_DINE.json), [Arc Linux DCR-association policy source and parameters](https://github.com/Azure/azure-policy/blob/master/built-in-policies/policyDefinitions/Monitoring/AzureMonitor_DCRA_Arc_Linux_DINE.json).

## Task 4: Assess and install updates with Azure Update Manager

Azure Update Manager uses Windows Update/WSUS or the configured Linux repositories to check for updates; it does not supply updates or bypass OS support/subscription requirements.

1. Open **Azure Update Manager > Machines** and filter to your subscription and RG. Select the **Arc-enabled** Windows and Linux machines.
2. Select **Check for updates** / **Assess now**. Wait for the assessment status and inspect failures rather than treating an empty update list as a successful assessment.
3. Enable periodic assessment using **Policy > Definitions**:
   - Definition: **Configure periodic checking for missing system updates on Azure Arc-enabled servers**.
   - Scope: your participant RG.
   - Parameters: **Assessment mode = AutomaticByPlatform** and **OS Type = Windows**.
   - Configure the remediation managed identity and required roles, then **create a remediation task** for the existing machine.
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

### Manually enable the Windows server

1. Open **Azure Arc > Machines**, select your Windows server and go to **Operations > Change tracking**.
2. In the DCR drop down choose "New Default Data Collection rule". Then in the Log Analytics drop down select your own workspace you created earlier in your resource group.
3. Click the **Enable** button. Follow the [current Arc quickstart](https://learn.microsoft.com/en-us/azure/azure-change-tracking-inventory/quickstart-monitor-changes-collect-inventory-azure-change-tracking-inventory).
4. After deployment, inspect the generated Change Tracking DCR (typically `ct-dcr-...`), its destination and its association. Do not assume it reused the workspace from Task 1.
5. If the flow cannot select your required workspace, create a dedicated CTI DCR using the current [Change Tracking DCR template procedure](https://learn.microsoft.com/en-us/azure/azure-change-tracking-inventory/create-data-collection-rule), in your participant RG with the Task 1 workspace resource ID. Associate that rule with the Arc machine through **Monitor > Data Collection Rules > your CTI rule > Resources > Add**. Keep **only one CTI DCR association per machine**.
6. Confirm AMA and the **ChangeTracking-Windows** extension are installed successfully. The [current overview](https://learn.microsoft.com/en-us/azure/azure-change-tracking-inventory/overview-monitoring-agent) requires Change Tracking extension **2.20.0.0 or later**. Do not copy older extension-version examples from historical screenshots.

### Enable the Linux server at scale with Azure Policy

Do **not** manually enable Change Tracking on Linux. Instead, use an RG-scoped policy initiative to onboard it and demonstrate how the same configuration can be enforced for additional Arc machines.

7. Open the **CTI DCR** created or selected during Windows onboarding and copy its full **resource ID**. Verify that its destination is your workspace from Task 1. Reuse this dedicated CTI rule, not the event/Syslog or OpenTelemetry performance DCR.
8. Open **Policy > Definitions**, filter to **Initiative** and the **Change Tracking and Inventory** category, and select **Enable ChangeTracking and Inventory for Arc-enabled virtual machines**. Choose the **Arc-enabled** initiative, not the Azure VM or VM scale set variant.
9. Select **Assign initiative**. Set **Scope** to your event subscription and **participant RG** and use an assignment name such as `mh-cti-arc`. Keep the Linux Arc machine in scope. The already configured Windows Arc machine is also evaluated; existing compliant components do not need remediation.
10. Under **Parameters**, show all parameters and configure:
    - **Effect for all constituent policies:** `DeployIfNotExists`.
    - **Data Collection Rule Resource Id:** the CTI DCR resource ID copied in step 7.
    - **Applicable Locations:** ensure the list includes the **Azure metadata locations of your Arc machine resources**. These are not necessarily the simulated Azure VMs' physical regions or the workspace region. Keep suitable defaults or select the applicable supported locations.
11. Configure a **system-assigned managed identity** for the policy assignment and select its metadata location. Review the initiative's required roles and confirm that they are granted to this identity at your participant RG, which contains the Arc machines and DCR. This is the **policy remediation identity**, not a new identity for the Linux guest. If role assignment fails, ask the coach rather than broadening the policy scope.
12. Review and create the assignment. **Wait for the first policy evaluation to complete before creating remediation tasks.**
    - Open **Policy > Compliance**, select the new assignment and refresh until resource-level compliance results are available for the Linux Arc machine and the applicable initiative definitions. Evaluation is asynchronous; an empty result or **Not started** is not a completed evaluation.
    - Confirm that the missing Linux Change Tracking components are reported as **Non-compliant**. Do not proceed to remediation while the Linux resource has not yet been evaluated. If it remains absent after evaluation completes, check the assignment scope and **Applicable Locations**.
13. Once the initial evaluation has completed, explicitly remediate the **existing** Linux Arc resource:
    - Open **Policy > Remediation**, select the assignment and confirm that the Linux machine is listed for the relevant non-compliant definition.
    - Create remediation tasks for each **non-compliant Linux `DeployIfNotExists` definition**: AMA installation if missing, Change Tracking extension installation, and CTI DCR association. An initiative assignment alone does not guarantee that all its definitions have been remediated.
    - AMA should already be present from Task 2. Do not reinstall it manually if its policy is compliant. Inspect individual remediation results and resolve failures before proceeding.
14. On the **Linux Arc resource**, verify that **ChangeTracking-Linux** is provisioned successfully and meets the extension-version requirement from step 6. In the CTI DCR's **Resources**, confirm that Linux is associated. Keep **only one CTI DCR association per machine**; the separate log and OpenTelemetry performance associations remain in place.
15. Check policy compliance for both Arc machines after a subsequent evaluation. New matching machines added to this RG are covered by the same assignment through normal policy evaluation; do not expect immediate deployment or ingestion.

After the extension and DCR have been deployed, it will take several minutes before any data will be visible in Azure. We suggest that you continue with the next challenge and revisit the verification step later.

### Verify inventory for both onboarding paths

In **Change Tracking and Inventory**, filter to your RG/machines and inspect **Inventory** / software data after initial collection.
Confirm that both the manually enabled **Windows** server and the policy-enabled **Linux** server report data. Successful remediation is not, on its own, proof of inventory ingestion.

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

References: [CTI overview and supported rollout methods](https://learn.microsoft.com/en-us/azure/azure-change-tracking-inventory/overview-monitoring-agent), [built-in Arc initiative and its parameters](https://github.com/Azure/azure-policy/blob/master/built-in-policies/policySetDefinitions/ChangeTrackingAndInventory/HybridVM.json), [at-scale portal onboarding](https://learn.microsoft.com/en-us/azure/azure-change-tracking-inventory/enable-change-tracking-at-scale-machines-blade), [ConfigurationData schema](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/configurationdata).

## Task 6: Verify guest performance and completion

1. Return to each **Arc machine > Monitoring > Insights** / **Monitor**.
2. Select **OpenTelemetry / metrics-based** if a selector is shown. Inspect guest CPU, memory, disk and network charts. Do not use the underlying Azure VM's host/platform metrics as proof of Arc guest collection.
3. Open **Azure Monitor's metrics explorer**, set its **scope to your Azure Monitor workspace** from Task 3, select the **PromQL editor**, and choose a recent time range, for example the last 30 minutes. Do not use **Log Analytics > Logs** or the workspace's own platform/ingestion-limit metrics. Run the following separately:

Current uptime in seconds, grouped by the originating resource:

```promql
max by ("Microsoft.resourceid") ({"system.uptime"})
```

Confirm that results include **both expected Arc machine resource IDs**, containing `/providers/Microsoft.HybridCompute/machines/`, and recent samples. A Windows result verifies the manual path; a Linux result verifies the policy path.

CPU utilization as a percentage, derived from the default CPU-time counter:

```promql
100 * (
  1 -
  (
    sum by ("Microsoft.resourceid") (rate({"system.cpu.time", state="idle"}[5m])) /
    sum by ("Microsoft.resourceid") (rate({"system.cpu.time"}[5m]))
  )
)
```

These queries use quoted OTel metric and attribute names with dots, as supported by Azure Monitor's PromQL editor. Do not silently substitute underscored metric names or query `InsightsMetrics` for this OTel-only setup.
The default sampling interval is 60 seconds. Allow enough samples for `rate()`; a blank initial graph or missing series is not success. Check the workspace, OTel DCR source/destination, machine association, agent, identity and outbound connectivity.
Logs and metrics reside in separate stores and require separate KQL and PromQL queries.

References: [Querying OTel system metrics with PromQL](https://learn.microsoft.com/en-us/azure/azure-monitor/metrics/prometheus-system-metrics-best-practices), [OTel collection verification](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/metrics-opentelemetry-guest-modify#verify-data-collection), [guest metrics and resource attributes](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/metrics-guest-reference).

4. Confirm all of the following before completing the challenge:
   - Both Arc machines are connected and AMA is healthy.
   - Windows and Linux test messages appear in `Event` and `Syslog`.
   - Your Azure Monitor workspace and its actual managed RG are identified and have the agreed governance tagging.
   - Windows was enabled manually; Linux received its OTel DCR association through the two RG-scoped Linux policy assignments, after initial evaluation and successful applicable remediation.
   - Update Manager has successful assessments and reviewed update installation results; periodic assessment alone is not patching.
   - Software inventory is visible in the correct workspace and CTI view.
   - Both Arc machine IDs have recent OpenTelemetry guest metric samples in your Azure Monitor workspace; Map/Dependency Agent and classic `InsightsMetrics` data are **not** success criteria.

If data is missing, troubleshoot the relevant service's extension, DCR, association, identity and network path.
Waiting a fixed ten minutes is not a substitute for checking those results.

You successfully completed challenge 2! 🚀🚀🚀