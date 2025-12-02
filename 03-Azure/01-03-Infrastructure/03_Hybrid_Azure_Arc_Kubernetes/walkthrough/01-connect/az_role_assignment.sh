# This is work in progress for Azure RBAC enablement 
# DO NOT USE YET


#!/bin/bash
# This script assigns the "Azure Arc Kubernetes Viewer" role to a specified Azure AD entity for a given Azure Arc Kubernetes cluster

export arc_resource_group='mh-arc-k8s'
export arc_cluster_name='mh-arc-enabled-k8s'

# get the resource id of the Azure Arc Kubernetes cluster
k8s_cluster_resource_id=$(az connectedk8s show --name $arc_cluster_name --resource-group $arc_resource_group --query id -o tsv)

# get the principal id of the Azure Arc Kubernetes cluster
#principal_id=$(az connectedk8s show --name $arc_cluster_name --resource-group $arc_resource_group --query identity.principalId -o tsv)

# assign the "Connected Cluster Managed Identity CheckAccess Reader" role to the cluster's managed identity
#az role assignment create --role "Connected Cluster Managed Identity CheckAccess Reader" --assignee $principal_id --scope $k8s_cluster_resource_id

# enable Azure RBAC for the Azure Arc Kubernetes cluster
#az connectedk8s enable-features -n $arc_cluster_name -g $arc_resource_group --features azure-rbac

# get the object id of the Azure AD entity (user, group, service principal, managed identity)
user_id=$(az ad signed-in-user show --query userPrincipalName -o tsv)

# required to access k8s resources from Azure portal
az role assignment create --role "Azure Arc Kubernetes Viewer" --assignee $user_id --scope $k8s_cluster_resource_id
az role assignment create --role "Azure Arc Enabled Kubernetes Cluster User Role" --assignee $user_id --scope $k8s_cluster_resource_id