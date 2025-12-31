#!/bin/bash

# Extract user number from Azure username (e.g., LabUser-37 -> 37)
azure_user=$(az account show --query user.name --output tsv)
user_number=$(echo $azure_user | sed -n 's/.*LabUser-\([0-9]\+\).*/\1/p')

connected_cluster_name="$user_number-k8s-arc-enabled"
resource_group="$user_number-k8s-arc"
custom_location="$user_number-onprem"
target_namespace="arc-data-services"

# Try to get Log Analytics workspace (optional - will be configured post-deployment if needed)
echo "Checking for Log Analytics workspace..."
law_resource_id=$(az monitor log-analytics workspace show --resource-group $resource_group --workspace-name "${user_number}-law" --query 'id' -o tsv)
law_shared_key=$(az monitor log-analytics workspace get-shared-keys --resource-group $resource_group --workspace-name "${user_number}-law" --query primarySharedKey -o tsv)

# Making extension install dynamic
# az config set extension.use_dynamic_install=yes_without_prompt

# required_extensions=("connectedk8s" "k8s-extension" "customlocation" "arcdata" "k8s-configuration")

# # loop through the array and check if each extension is installed
# for extension in "${required_extensions[@]}"; do
#     echo "Checking if you have up-to-date Azure Arc AZ CLI '$extension' extension..."
#     az extension show --name "$extension" &> extension_output
#     if cat extension_output | grep -q "not installed"; then
#         az extension add --name "$extension"
#     else
#         az extension update --name "$extension"
#     fi
#     rm extension_output
#     echo ""
# done

# echo "Registering required resource providers..."
# az provider register --namespace Microsoft.Kubernetes --wait
# az provider register --namespace Microsoft.KubernetesConfiguration --wait
# az provider register --namespace Microsoft.ExtendedLocation --wait
# az provider register --namespace Microsoft.AzureArcData --wait
# az provider register --namespace Microsoft.RedHatOpenShift --wait

# echo Installing Azure Arc-enabled data services extension
# az k8s-extension create \
#     --name arc-data-services \
#     --extension-type microsoft.arcdataservices \
#     --cluster-type connectedClusters \
#     --cluster-name $connected_cluster_name \
#     --resource-group $resource_group \
#     --auto-upgrade false \
#     --scope cluster \
#     --version 1.18.0 \
#     --release-namespace $target_namespace \
#     --config Microsoft.CustomLocation.ServiceAccount=sa-arc-bootstrapper  
#     # TODO: check whether service account can be found if it's in another namespace
#     #TODO: check whether this version is the latest stable version

# echo "Waiting for extension to be ready..."
# sleep 15

# echo "Getting connected cluster and extension IDs..."
# connected_cluster_id=$(az connectedk8s show --name $connected_cluster_name --resource-group $resource_group --query id -o tsv)
# extension_id=$(az k8s-extension show --name arc-data-services --cluster-type connectedClusters --cluster-name $connected_cluster_name --resource-group $resource_group --query id -o tsv)

echo "Enabling custom location feature..."
# az customlocation create \
#     --name $custom_location \
#     --resource-group $resource_group \
#     --namespace $target_namespace \
#     --host-resource-id $connected_cluster_id \
#     --cluster-extension-ids $extension_id
az connectedk8s enable-features 
    --name $connected_cluster_name \
    --resource-group $resource_group \
    --features cluster-connect custom-locations

# echo "Waiting for custom location to be ready..."
# sleep 15
# custom_location_id=$(az customlocation show --name $custom_location --resource-group $resource_group --query id -o tsv)

echo "Setting up credentials for data controller..."
#TODO: Parse from arc-data-credentials.yaml instead of hardcoding credentials
export AZDATA_USERNAME="data_user"
export AZDATA_PASSWORD="ComplexSecurePassword123!"
# export AZDATA_LOGSUI_USERNAME="logs_user"
# export AZDATA_LOGSUI_PASSWORD="ComplexSecurePassword123!"
# export AZDATA_METRICSUI_USERNAME="metrics_user"
# export AZDATA_METRICSUI_PASSWORD="ComplexSecurePassword123!"

export AZDATA_LAW_WORKSPACE_ID="$law_resource_id"
export AZDATA_LAW_SHARED_KEY="$law_shared_key"

echo "Creating Arc Data Controller..."
az arcdata dc create \
    --name arc-data-controller \
    --resource-group $resource_group  \
    --cluster-name $connected_cluster_name \
    --connectivity-mode direct \
    --profile-name azure-arc-kubeadm \
    --auto-upload-metrics true \
    --auto-upload-logs true \
    --custom-location $custom_location \
    --storage-class local-path 
# az arcdata dc create \
#     --name arc-data-controller \
#     --resource-group $resource_group \
#     --custom-location $custom_location \
#     --cluster-name $connected_cluster_name \
#     --connectivity-mode direct \
#     --profile-name azure-arc-kubeadm \
#     --auto-upload-metrics true --auto-upload-logs true \
#     --storage-class local-path \
#     --infrastructure onpremises \
#     --k8s-namespace $target_namespace

# az deployment group create \
#     --resource-group $resource_group \
#     --name "$user_number-dc-depl" \
#     --template-file "./dataController.json" \
#     --parameters "./dataController.parameters.json"
