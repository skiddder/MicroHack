#!/bin/bash
# This script connects an existing K3s cluster to Azure Arc with Azure RBAC enabled
echo "Exporting environment variables"

# Extract user number from Azure username (e.g., LabUser-37 -> 37)
azure_user=$(az account show --query user.name --output tsv)
user_number=$(echo $azure_user | sed -n 's/.*LabUser-\([0-9]\+\).*/\1/p')

if [ -z "$user_number" ]; then
    echo "Error: Could not extract user number from Azure username: $azure_user"
    echo "Please make sure you're logged in as LabUser-XX"
    exit 1
fi

echo "Detected user number: $user_number"

# Set variables based on detected user number
export onprem_resource_group="${user_number}-k8s-onprem"
export arc_resource_group="${user_number}-k8s-arc"
export arc_cluster_name="${user_number}-k8s-arc-enabled"
export location="westeurope"

echo "Using resource groups: $onprem_resource_group (onprem) and $arc_resource_group (arc)"

# Registering Azure Arc providers
echo "Registering Azure Arc providers"
az provider register --namespace Microsoft.Kubernetes --wait
az provider register --namespace Microsoft.KubernetesConfiguration --wait
az provider register --namespace Microsoft.ExtendedLocation --wait

az provider show -n Microsoft.Kubernetes -o table
az provider show -n Microsoft.KubernetesConfiguration -o table
az provider show -n Microsoft.ExtendedLocation -o table

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
    --infrastructure 'generic' \
    --distribution 'k3s'

echo "Waiting for Arc connection to be established..."
sleep 30

echo "Verifying Arc connection status..."
az connectedk8s show --resource-group $arc_resource_group --name $arc_cluster_name --query "{name:name, connectivityStatus:connectivityStatus}"

echo ""
echo "✅ Azure Arc connection completed successfully!"
echo ""
echo "📋 Summary:"
echo "   - Cluster: $arc_cluster_name"
echo "   - Resource Group: $arc_resource_group" 
echo "   - Status: Connected"
echo ""
echo "🌐 You can view the cluster in Azure Portal:"
echo "   https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id --output tsv)/resourceGroups/$arc_resource_group/providers/Microsoft.Kubernetes/connectedClusters/$arc_cluster_name"
echo ""
echo "📝 Note: You will need to provide an access token to view Kubernetes resources in the portal."

