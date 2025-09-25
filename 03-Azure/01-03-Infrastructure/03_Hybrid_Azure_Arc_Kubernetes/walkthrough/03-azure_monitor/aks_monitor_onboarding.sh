#!/bin/sh

# TODO: Replace this script by terraform (https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-monitoring-enable?tabs=terraform#enable-prometheus-and-grafana)
# TODO: optional use the following extension for container insights
#az k8s-extension create --name "azuremonitor-containers" --cluster-name $connectedClusterName --resource-group $Env:resourceGroup --cluster-type connectedClusters --extension-type Microsoft.AzureMonitor.Containers --configuration-settings logAnalyticsWorkspaceResourceID=$workspaceId
# TODO: ensure providers are registered (https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-monitoring-enable)

# <--- Change the following environment variables according to your Azure service principal name --->

echo "Exporting environment variables"
export arc_resource_group='mh-arc-aks'
export arc_cluster_name='arc-enabled-K8s'

echo "Downloading the Azure Monitor onboarding script"
curl -o enable-monitoring.sh -L https://aka.ms/enable-monitoring-bash-script

echo "Onboarding the Azure Arc-enabled Kubernetes cluster to Azure Monitor for containers"
export resource_id=$(az resource show --resource-group $resourceGroup --name $arcClusterName --resource-type "Microsoft.Kubernetes/connectedClusters" --query id -o tsv)
export kubeContext="$(kubectl config current-context)"
bash enable-monitoring.sh --resource-id $azureArcClusterResourceId --client-id $appId --client-secret $password --tenant-id $tenantId --kube-context $kubeContext

echo "Cleaning up"
rm enable-monitoring.sh
