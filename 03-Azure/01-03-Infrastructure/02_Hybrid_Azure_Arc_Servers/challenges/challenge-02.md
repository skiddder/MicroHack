# Challenge 2 - Azure Monitor integration

[Previous Challenge Solution](challenge-01.md) - **[Home](../Readme.md)** - [Next Challenge Solution](challenge-03.md)

## Goal

In challenge 2 you will monitor your Windows and Linux Arc-enabled servers using Azure Monitor Agent (AMA), OpenTelemetry guest performance metrics, and Change Tracking and Inventory. Enable performance monitoring manually for Windows, then use Azure Policy for Linux to demonstrate the at-scale approach. You will also assess and install updates with Azure Update Manager, which does not depend on AMA or a Log Analytics workspace.

## Actions

- Create all necessary Azure resources
  - Log Analytics workspace (Name: mh-arc-servers-automation-law)
  - Azure Monitor workspace for OpenTelemetry metrics (participant-specific name, for example mh-amw-labuser-0001)
  - Identify its automatically created managed resource group and apply the required governance tagging
- Configure Data Collection Rules to collect Windows event logs and Linux syslog
- Manually enable OpenTelemetry guest metrics on the Windows Arc machine, using the default system metrics
- Use RG-scoped Linux Arc policies to ensure AMA and associate the same OpenTelemetry DCR with Linux; wait for policy evaluation before remediating the existing machine
- Enable and configure Update Manager
- Enable Change Tracking and Inventory


## Success criteria

- You have a Log Analytics workspace for logs/inventory and a separate Azure Monitor workspace for guest metrics
- Your Azure Monitor workspace's managed RG is identified and has the required governance tagging
- Windows was enabled manually; Linux was enabled through the AMA and DCR-association policies at your Azure exercise RG scope, with successful applicable remediation after evaluation
- You can query the Log Analytics Workspace for events of your virtual machines
- All virtual machines have the latest Windows and Linux updates installed
- You can browse through the software inventory of your virtual machines
- You can inspect the OpenTelemetry guest-performance charts and query recent metrics for both Arc machine resource IDs using PromQL in your Azure Monitor workspace
- Classic performance ingestion, Dependency Agent/Map, per-process metrics and an Azure Managed Grafana workspace are not required

## Learning resources

- [Create a Log Analytics workspace in the Azure portal](https://docs.microsoft.com/azure/azure-monitor/logs/quick-create-workspace)
- [Deployment options for Azure Monitor agent on Azure Arc-enabled servers](https://learn.microsoft.com/azure/azure-arc/servers/concept-log-analytics-extension-deployment)
- [Data collection rules in Azure Monitor](https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-overview)
- [Azure Policy built-in definitions for Azure Arc-enabled servers](https://docs.microsoft.com/azure/azure-arc/servers/policy-reference)
- [Azure Update Manager](https://learn.microsoft.com/azure/update-manager/overview)
- [Enable Change Tracking and Inventory using Azure Monitor Agent](https://learn.microsoft.com/en-us/azure/azure-change-tracking-inventory/quickstart-monitor-changes-collect-inventory-azure-change-tracking-inventory)
- [OpenTelemetry metrics-based monitoring for VMs and Arc-enabled servers](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/metrics-opentelemetry-guest)
- [Create an Azure Monitor workspace](https://learn.microsoft.com/en-us/azure/azure-monitor/metrics/azure-monitor-workspace-manage)
- [Enable enhanced monitoring in the portal](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/tutorial-enable-monitoring)
- [OTel DCR configuration and Arc associations](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vm-enable-monitoring)
- [Use Azure Policy to deploy AMA and DCR associations](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-policy)
- [PromQL for OTel guest metrics](https://learn.microsoft.com/en-us/azure/azure-monitor/metrics/prometheus-system-metrics-best-practices)
