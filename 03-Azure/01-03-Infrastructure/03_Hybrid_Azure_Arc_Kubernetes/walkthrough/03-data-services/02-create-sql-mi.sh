#!/bin/bash

export customlocation_name='onprem-aks-cl'
export arc_resource_group='mh-arc-aks'
export sqlmi_name='sql-mi-03'

echo "Creating SQL Managed Instance $sqlmi_name in resource group $arc_resource_group and custom location $customlocation_name ..."
az sql mi-arc create --name $sqlmi_name \
    --resource-group $arc_resource_group \
    --custom-location $customlocation_name \
    --cores-request 1 \
    --memory-request 3Gi