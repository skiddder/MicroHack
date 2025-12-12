#!/bin/bash

## variables for Azure subscription, resource group, cluster name, location, extension, and namespace.
export arc_resource_group='mh-arc-aks'
export arc_cluster_name='mh-arc-enabled-K8s'
export custom_location_name='mh-custom-data-location'

## variables for Log Analytics
# todo: Where do these come from? Fetch automatically
#export log_analytics_workspace_guid='e52c449f-e086-472c-b8dc-b51fd51f2650'
#export log_analytics_key='QhivRkp/e6rSzZSFBE6jENJvLlBSpjoKRWo5S/MZEVTTb7/UCi8H764pxdUxOOLG8hCwCxUDi8XEWPeiJ0LZcw=='

## variables for logs and metrics dashboard credentials
export AZDATA_LOGSUI_USERNAME='adm-simon'
export AZDATA_LOGSUI_PASSWORD='#Start12345!'
export AZDATA_METRICSUI_USERNAME='adm-simon'
export AZDATA_METRICSUI_PASSWORD='#Start12345!'

## variables for SQL Managed Instance
export sql_mi_name='mh-sql-mi-arc'

subscription_id=$(az account show --query id --output tsv)

# todo: use variables and clean up
#export workspaceId=$(az resource show --resource-group mh-arc-cloud --name mh-arc-law --resource-type "Microsoft.OperationalInsights/workspaces" --query properties.customerId -o tsv)

echo "Creating Azure Arc Data Controller 'arc-data-controller' (including custom location '$custom_location_name')..."
az arcdata dc create \
--name arc-data-controller \
-g $arc_resource_group \
--connectivity-mode indirect \
--profile-name azure-arc-aks-premium-storage \
--storage-class managed-csi-premium \
--location westeurope \
--use-k8s \
--k8s-namespace arc-data-controller \
--infrastructure azure
#--custom-location $custom_location_name \
#--cluster-name $arc_cluster_name \
#--auto-upload-metrics true \
#--auto-upload-logs true \

az arcdata dc status show -n arc-data-controller -g $arc_resource_group --query properties.k8SRaw.status.state -o tsv

echo "Createing SQL MI..."
az sql mi-arc create \
--name $sql_mi_name \
--resource-group $arc_resource_group \
-–subscription $subscription_id \
--custom-location $custom_location_name