# Challenge 2 - Azure Monitor integration

[Previous Challenge Solution](challenge-01.md) - **[Home](../Readme.md)** - [Next Challenge Solution](challenge-03.md)

## Goal

In challenge 2 you will monitor your Windows and Linux Arc-enabled servers using Azure Monitor Agent (AMA), Change Tracking and Inventory, and VM insights. You will also assess and install updates with Azure Update Manager, which does not depend on AMA or a Log Analytics workspace.

## Actions

- Create all necessary Azure resources
  - Log Analytics workspace (Name: mh-arc-servers-automation-law)
- Configure Data Collection Rules to collect Windows event logs and Linux syslog
- Enable Azure Monitor for Azure Arc-enabled Servers with Azure Policy initiative
- Enable and configure Update Manager
- Enable Change Tracking and Inventory
- Enable VM Insights


## Success criteria

- You have a Log Analytics Workspace
- You successfully linked the necessary Azure Policy initiative to the Azure resource group
- You can query the Log Analytics Workspace for events of your virtual machines
- All virtual machines have the latest Windows and Linux updates installed
- You can browse through the software inventory of your virtual machines
- You can use classic VM insights to inspect guest performance; Dependency Agent/Map is not required. The walkthrough explains the distinction from the newer OpenTelemetry metrics experience.

## Learning resources

- [Create a Log Analytics workspace in the Azure portal](https://docs.microsoft.com/azure/azure-monitor/logs/quick-create-workspace)
- [Deployment options for Azure Monitor agent on Azure Arc-enabled servers](https://learn.microsoft.com/azure/azure-arc/servers/concept-log-analytics-extension-deployment)
- [Data collection rules in Azure Monitor](https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-overview)
- [Azure Policy built-in definitions for Azure Arc-enabled servers](https://docs.microsoft.com/azure/azure-arc/servers/policy-reference)
- [Azure Update Manager](https://learn.microsoft.com/azure/update-manager/overview)
- [Enable Change Tracking and Inventory using Azure Monitor Agent](https://learn.microsoft.com/en-us/azure/azure-change-tracking-inventory/quickstart-monitor-changes-collect-inventory-azure-change-tracking-inventory)
- [Monitor a hybrid machine with VM insights](https://learn.microsoft.com/en-us/azure/azure-arc/servers/tutorial-enable-vm-insights)
