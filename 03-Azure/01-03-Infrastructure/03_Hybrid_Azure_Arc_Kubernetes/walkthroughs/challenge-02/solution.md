# Walkthrough Challenge 2 - Enable Azure Monitor for Containers

## Prerequisites
* You require at least Contributor access to the cluster for onboarding.
* You require Monitoring Reader or Monitoring Contributor to view data after monitoring is enabled.
* Verify the firewall requirements in addition to the Azure Arc-enabled Kubernetes network requirements.
* A Log Analytics workspace (law). (If you used the terraform to deploy the microhack environment, each participant already has a law in his arc resource group.)
* You must be logged in to az cli (az login)

## Task 1 - Enable Azure Monitor for k8s
Execute the following commands in your bash shell to install the container log extension with default settings:
```bash
# Extract user number - assuming user names like i.e. LabUser-37
user_postfix=$(az account show --query user.name -o tsv | sed -n 's/.*LabUser-\([0-9]\+\).*/\1/p')
echo $user_postfix

# if you are running this in your own env, adjust the values to match your env
export arc_resource_group="$user_postfix-k8s-arc" 
export arc_cluster_name="$user_postfix-k8s-arc-enabled"
export law_resource_id=$(az monitor log-analytics workspace show --resource-group $arc_resource_group --workspace-name "${user_postfix}-law" --query 'id' -o tsv)

az k8s-extension create \
    --name azuremonitor-containers \
    --cluster-name $arc_cluster_name \
    --resource-group $arc_resource_group \
    --cluster-type connectedClusters  \
    --extension-type Microsoft.AzureMonitor.Containers \
    --configuration-settings azure-monitor-workspace-resource-id=$arc_resource_group

```
The output should look roughly like this:
```bash
Ignoring name, release-namespace and scope parameters since microsoft.azuremonitor.containers only supports cluster scope and single instance of this extension.
Defaulting to extension name 'azuremonitor-containers' and release-namespace 'azuremonitor-containers'
{
 [...]
  "isSystemExtension": false,
  "name": "azuremonitor-containers",
  "packageUri": null,
  "plan": null,
  "provisioningState": "Succeeded",
  "releaseTrain": "Stable",
  "resourceGroup": "37-k8s-arc",
  "scope": {
    "cluster": {
      "releaseNamespace": "azuremonitor-containers"
    },
    "namespace": null
  },
 [...]
  "type": "Microsoft.KubernetesConfiguration/extensions",
  "version": null
}
```

To verify the installation, navigate to your arc-enabled k8s cluster in the Azure portal. 
* In the left navigation pane in section Monitoring select Insights. Then in the main windows check the tabs Cluster, Reports, Nodes, Controllers and Containers. You should see a dashboard in each tab.
* In tab Containers find "clusterconnectservice-operator" and click the title. This opens an Overview pane on the right hand side. Click on "View in Log Analytics" to see the stdout logs of this container.

## Task 2 - Enable Defender for Containers Plan
To enable the Defender for Containers plan on your subscription, 
* Open the [Defender for Cloud | Environment settings](https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/EnvironmentSettings)
* At the bottom of your page find your subscription and click the elipses on the right hand side, then in the popup click "Edit settings".
![environment-settings](img/01_env_settings.png)
* In section Cloud Workload Protection (CWPP) find the line for the Containers Plan and click the "Settings" links in that line.
![container-plan-setting](img/02_container_plan_settings.png)
* In the Settings & monitoring page ensure the following settings are turned on (please note that you are working with several participants in the same subscription. Someone might already turned on the recommended settings.):
    * Defender sensor - Required because Arc clusters do not have agentless telemetry collection like AKS. Installs the Defender sensor DaemonSet on every node for runtime threat detection.
    * Azure Policy - Installs Gatekeeper/OPA in your Arc cluster. Required for Kubernetes posture management, admission control, and workload hardening.
    * Kubernetes API access - sets permissions to allow API-based discovery of your Kubernetes clusters. For Arc, this enables Defender to read Kubernetes API objects for configuration assessment.
    * Registry access - Vulnerability assessment scanning for images stored in ACR registries. It does NOT scan non‑Azure registries.
* When finished click on the Continue link at the top of the page:
![settings_n_monitoring](img/03_settings_n_monitoring.png)
* If you made changes, they are not yet saved. Make sure to click the Save link at the top of the page:
![save](img/04_save.png)


## Task 3 - Deploy Defender for Container

For Arc‑enabled Kubernetes, Defender for Containers cannot operate agentlessly the way it does on AKS. Arc clusters require the Defender sensor DaemonSet to be deployed.

If auto‑provisioning is enabled in the portal (the toggle “Defender sensor” → ON”), then Defender for Cloud will attempt to deploy the sensor automatically using the Arc extension mechanism.
If you want to force it (recommended), use:

```bash
az k8s-extension create \
  --name microsoft.azuredefender.kubernetes \
  --cluster-type connectedClusters \
  --cluster-name $arc_cluster_name \
  --resource-group $arc_resource_group \
  --extension-type microsoft.azuredefender.kubernetes \
  --configuration-settings logAnalyticsWorkspaceResourceID=$law_resource_id
```

If you run into an error telling you "Helm installation failed : Resource already existing in your cluster" Defender for Cloud already installed the extension successfully.

Check Policy recommendations in Defender for Cloud: 
* In the Azure Portal > Defender for Cloud > Cloud Security > Workload protections > Kubernetes > Recommendations
* If the cluster is receiving:

Misconfiguration findings
Workload hardening recommendations
Policy‑related recommendations

…then the backend integration is working.

You successfully completed challenge 2! 🚀🚀🚀

[Back to the challenges](../../Readme.md#challenge-3---kaito) - [Next Challenge's Solution]()