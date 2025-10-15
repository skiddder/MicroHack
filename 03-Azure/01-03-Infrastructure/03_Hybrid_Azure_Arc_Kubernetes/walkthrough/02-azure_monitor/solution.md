### Prerequisites
* You require at least Contributor access to the cluster for onboarding.
* You require Monitoring Reader or Monitoring Contributor to view data after monitoring is enabled.
* Verify the firewall requirements in addition to the Azure Arc-enabled Kubernetes network requirements.

### Solution
Execute the following cli command to install the monitoring extension with default settings:
```bash
export arc_resource_group='mh-arc-aks'
export arc_cluster_name='mh-arc-enabled-K8s'

az k8s-extension create \
    --name azuremonitor-containers \
    --cluster-name $arc_cluster_name \
    --resource-group $arc_resource_group \
    --cluster-type connectedClusters \
    --extension-type Microsoft.AzureMonitor.Containers
```

### Optional: Enable Prometheus and Grafana

### Resources
* [Enable monitoring for Arc-enabled Kubernetes clusters](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-monitoring-enable-arc?tabs=cli)