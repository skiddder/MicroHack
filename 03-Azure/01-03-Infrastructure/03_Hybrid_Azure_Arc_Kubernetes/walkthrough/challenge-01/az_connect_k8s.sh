#!/bin/bash
# exit on first error
set -e

# This script connects an existing K3s cluster to Azure Arc with Azure RBAC enabled
echo "Exporting environment variables"

if [ -f "$HOME/.microhack-k8s.env" ]; then
    source "$HOME/.microhack-k8s.env"
fi

# Extract user number from Azure username (e.g., LabUser-37 -> 37)
azure_user=$(az account show --query user.name --output tsv)
azure_user="${azure_user//$'\r'/}"
lab_user="${azure_user%%@*}"
hb_resource_group="rg-${lab_user,,}"
user_number="${user_number:-$(echo "$azure_user" | cut -d'@' -f1 | sed -E -n 's/.*[^0-9]([0-9]+)$/\1/p' | sed 's/^0*//')}"

if [ -z "$user_number" ]; then
    echo "Error: Could not extract user number from Azure username: $azure_user"
    echo "Please make sure you're logged in as LabUser-XX"
    exit 1
fi

echo "Detected user number: $user_number"

if [ -z "${arc_resource_group:-}" ]; then
    hb_group_exists=$(az group exists --name "$hb_resource_group")
    if [ "$hb_group_exists" = "true" ]; then
        arc_resource_group="$hb_resource_group"
    else
        legacy_resource_group="${user_number}-k8s-arc"
        legacy_group_exists=$(az group exists --name "$legacy_resource_group")
        if [ "$legacy_group_exists" != "true" ]; then
            echo "Error: Neither '$hb_resource_group' nor '$legacy_resource_group' exists in the selected subscription." >&2
            echo "Set arc_resource_group and onprem_resource_group to the names from your HB Console Credentials." >&2
            exit 1
        fi
        arc_resource_group="$legacy_resource_group"
    fi
fi

if [ "$arc_resource_group" = "$hb_resource_group" ]; then
    export onprem_resource_group="${onprem_resource_group:-${arc_resource_group}-onprem}"
    if [ -z "${arc_cluster_name:-}" ]; then
        master_vm_name=$(az vm list --resource-group "$onprem_resource_group" --query "[?ends_with(name, '-k8s-master')].name | [0]" --output tsv)
        if [ -z "$master_vm_name" ]; then
            echo "Error: No K3s master VM found in '$onprem_resource_group'; cannot derive the Arc cluster name." >&2
            exit 1
        fi
        arc_cluster_name="${master_vm_name%-k8s-master}-k8s-arc-enabled"
    fi
else
    export onprem_resource_group="${onprem_resource_group:-${user_number}-k8s-onprem}"
fi
export arc_resource_group
export arc_cluster_name="${arc_cluster_name:-${user_number}-k8s-arc-enabled}"
if [ -z "${location:-}" ]; then
    location=$(az group show --name "$arc_resource_group" --query location --output tsv)
fi
export location
if [ -z "$location" ]; then
    echo "Error: Could not determine the location of '$arc_resource_group'." >&2
    exit 1
fi

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

echo "Checking if you have up-to-date Azure Arc AZ CLI 'connectedk8s' extension..."
if ! az extension show --name connectedk8s > /dev/null 2>&1; then
    az extension add --name connectedk8s
else
    az extension update --name connectedk8s
fi
echo ""

echo "Checking if you have up-to-date Azure Arc AZ CLI 'k8s-configuration' extension..."
if ! az extension show --name k8s-configuration > /dev/null 2>&1; then
    az extension add --name k8s-configuration
else
    az extension update --name k8s-configuration
fi
echo ""

echo "Connecting the cluster to Azure Arc"
az connectedk8s connect --name "$arc_cluster_name" \
    --resource-group "$arc_resource_group" \
    --location "$location" \
    --infrastructure 'generic' \
    --distribution 'k3s'

echo "Waiting for Arc connection to be established..."
sleep 30

echo ""
echo "Summary:"
echo "   - Resource Group: $arc_resource_group" 
echo "   - Status:"
az connectedk8s show --resource-group "$arc_resource_group" --name "$arc_cluster_name" --query "{name:name, connectivityStatus:connectivityStatus}"
