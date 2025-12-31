#!/bin/bash
export arc_resource_group='37-k8s-arc'      # <-- you can change this according to your naming convention
export arc_cluster_name='aks-test-arc'
export customlocation_name='onprem-aks-cl'       # <-- you can change this according to your naming convention
export extensionInstanceName="arc-data-services" # <-- you can change this according to your naming convention
export arc_data_namespace="arc-data-controller"  # <-- you can change this according to your naming convention
#export storageclass="managed-csi-premium"
export arc_data_profile_name='azure-arc-aks-default-storage'


# add an array with the names of required extensions
required_extensions=("connectedk8s" "k8s-extension" "customlocation")

# loop through the array and check if each extension is installed
for extension in "${required_extensions[@]}"; do
    echo "Checking if you have up-to-date Azure Arc AZ CLI '$extension' extension..."
    az extension show --name "$extension" &> extension_output
    if cat extension_output | grep -q "not installed"; then
        az extension add --name "$extension"
    else
        az extension update --name "$extension"
    fi
    rm extension_output
    echo ""
done

# check if extended location provider is registered
echo "Checking if Extended Location provider is registered..."
az provider show --namespace Microsoft.ExtendedLocation &> provider_output
if cat provider_output | grep -q "NotRegistered"; then
    echo "Registering Extended Location provider..."
    az provider register --namespace Microsoft.ExtendedLocation --wait
    echo "Extended Location provider registered."
else
    echo "Extended Location provider is already registered."
fi
rm provider_output
echo ""

# enable custom location feature 
echo "Enabling custom location feature..."
# using the service principal id
#az ad sp show --id bc313c14-388c-4e7d-a58e-70017303ee3b --query id -o tsv &> spid
#az connectedk8s enable-features -n $arc_cluster_name -g $arc_resource_group --custom-locations-oid $(cat spid) --features cluster-connect custom-locations
# using entra user
az connectedk8s enable-features -n $arc_cluster_name \
    -g $arc_resource_group \
    --features cluster-connect custom-locations

## deploy cluster extension for arc-enabled data services
echo "Creating Azure Arc data services extension..."
az arcdata dc create --name $extensionInstanceName \
    -g $arc_resource_group \
    --custom-location $customlocation_name \
    --cluster-name $arc_cluster_name \
    --connectivity-mode direct \
    --profile-name $arc_data_profile_name \
    --auto-upload-metrics true --auto-upload-logs true \
    #--storage-class $storageclass <-- optional, uncomment if you want to override the storage class provided by the profile


# THE BLOCK BELOW IS NOT REQUIRED ANYMORE AS THE EXTENSION CREATION COMMAND ABOVE PROVISIONS THE CUSTOM LOCATION AUTOMATICALLY

# # get arc-enabled kubernetes resourcemanager id
# connectedClusterId=$(az connectedk8s show -n $arc_cluster_name -g $arc_resource_group  --query id -o tsv)
# # get arc-enabled data services extension id
# extensionId=$(az k8s-extension show --name $extensionInstanceName --cluster-type connectedClusters -c $arc_cluster_name -g $arc_resource_group  --query id -o tsv)
# # create custom location
# echo "Creating custom location..."
# az customlocation create -n $customlocation_name -g $arc_resource_group --namespace $arc_data_namespace --host-resource-id $connectedClusterId --cluster-extension-ids $extensionId

# validate if custom location provisioned successfully
echo "Validating if the feature is enabled..."
az customlocation show -g $arc_resource_group -n $customlocation_name

echo ""
echo "Validating if the arc datacontroller is created..."
kubectl get datacontrollers -n onprem-aks-cl