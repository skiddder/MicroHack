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

## Task 2 - Deploy Defender for Containers

## Task 3 -

You successfully completed challenge 2! 🚀🚀🚀

[Back to the challenges](../../Readme.md#challenge-3---kaito) - [Next Challenge's Solution]()