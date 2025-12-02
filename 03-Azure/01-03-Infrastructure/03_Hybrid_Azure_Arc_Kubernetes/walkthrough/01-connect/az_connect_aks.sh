#!/bin/bash
# This script connects an existing AKS cluster to Azure Arc
echo "Exporting environment variables"

export onprem_aks_cluster_name='onprem-k8s'
export onprem_resource_group='mh-arc-k8s-onprem'
export arc_resource_group='mh-arc-k8s'
export arc_cluster_name='mh-arc-enabled-k8s'
export location="westeurope"

# Registering Azure Arc providers
echo "Registering Azure Arc providers"
az provider register --namespace Microsoft.Kubernetes --wait
az provider register --namespace Microsoft.KubernetesConfiguration --wait
az provider register --namespace Microsoft.ExtendedLocation --wait

az provider show -n Microsoft.Kubernetes -o table
az provider show -n Microsoft.KubernetesConfiguration -o table
az provider show -n Microsoft.ExtendedLocation -o table

# Getting AKS credentials
echo "Getting AKS credentials (kubeconfig)"
az aks get-credentials --name $onprem_aks_cluster_name --resource-group $onprem_resource_group --overwrite-existing

echo "Clear cached helm Azure Arc Helm Charts"
rm -rf ~/.azure/AzureArcCharts

# Installing Azure Arc k8s CLI extensions
echo "Checking if you have up-to-date Azure Arc AZ CLI 'connectedk8s' extension..."
az extension show --name "connectedk8s" &> extension_output
if cat extension_output | grep -q "not installed"; then
    az extension add --name "connectedk8s"
else
    az extension update --name "connectedk8s"
fi
rm extension_output
echo ""

echo "Checking if you have up-to-date Azure Arc AZ CLI 'k8s-configuration' extension..."
az extension show --name "k8s-configuration" &> extension_output
if cat extension_output | grep -q "not installed"; then
    az extension add --name "k8s-configuration"
else
    az extension update --name "k8s-configuration"
fi
rm extension_output
echo ""

echo "Connecting the cluster to Azure Arc"
az connectedk8s connect --name $arc_cluster_name \
    --resource-group $arc_resource_group \
    --location $location \
    --infrastructure 'azure' \
    --distribution 'aks'

