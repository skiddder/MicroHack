#!/bin/bash

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
export arc_resource_group="${user_number}-k8s-arc"
export arc_cluster_name="${user_number}-k8s-arc-enabled"
export customlocation_name="${user_number}-customlocation"
export extension_instance_name="arc-data-services"  
export arc_data_namespace="arc-data-controller"     
# For K3s, the default storage class is typically 'local-path'
export storage_class="local-path"
export arc_data_profile_name="azure-arc-kubeadm"

# Try to get Log Analytics workspace (optional - will be configured post-deployment if needed)
echo "Checking for Log Analytics workspace..."
law_resource_id=$(az monitor log-analytics workspace show --resource-group $arc_resource_group --workspace-name "${user_number}-law" --query 'id' -o tsv 2>/dev/null || echo "")
if [ -n "$law_resource_id" ]; then
    echo "Found Log Analytics workspace: ${user_number}-law"
else
    echo "Log Analytics workspace not found - monitoring can be configured later"
fi


# add an array with the names of required extensions
required_extensions=("connectedk8s" "k8s-extension" "customlocation" "arcdata")

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

# Verify storage class availability for K3s
echo "Checking available storage classes..."

# Verify the expected storage class exists
if ! kubectl get storageclass $storage_class &>/dev/null; then
    echo "Warning: Storage class '$storage_class' not found. Available storage classes:"
    kubectl get storageclass
    echo "Please ensure a suitable storage class is available before proceeding."
    echo "For K3s, you may need to use 'local-path' or create a custom storage class."
else
    echo "Storage class '$storage_class' is available."
fi
echo ""

# enable custom location feature 
echo "Enabling custom location feature..."

# using entra user
az connectedk8s enable-features \
    --name $arc_cluster_name \
    --resource-group $arc_resource_group \
    --features cluster-connect custom-locations

## deploy cluster extension for arc-enabled data services
echo "Creating Azure Arc data services extension..."

# Set environment variables for Log Analytics integration if workspace is available
if [ -n "$law_resource_id" ]; then
    echo "Setting up Log Analytics integration..."
    export WORKSPACE_ID=$law_resource_id
    # Get the workspace shared key
    law_shared_key=$(az monitor log-analytics workspace get-shared-keys --resource-group $arc_resource_group --workspace-name "${user_number}-law" --query 'primarySharedKey' -o tsv 2>/dev/null || echo "")
    if [ -n "$law_shared_key" ]; then
        export WORKSPACE_SHARED_KEY=$law_shared_key
        echo "Log Analytics workspace credentials configured."
    else
        echo "Could not retrieve workspace shared key - logs may need manual configuration."
    fi
fi

# Load credentials from YAML configuration file
CREDS_FILE="$(pwd)/arc-data-credentials.yaml"
echo "Loading Arc Data Services credentials from YAML..."

# Simple YAML parsing using basic shell tools (no external dependencies)
export AZDATA_LOGSUI_USERNAME=$(grep -A1 "logs:" "$CREDS_FILE" | grep "username:" | sed 's/.*username: *//; s/[\"'\'']//g' | tr -d '\r\n' | xargs)
export AZDATA_LOGSUI_PASSWORD=$(grep -A2 "logs:" "$CREDS_FILE" | grep "password:" | sed 's/.*password: *//; s/[\"'\'']//g' | tr -d '\r\n' | xargs)
export AZDATA_METRICSUI_USERNAME=$(grep -A1 "metrics:" "$CREDS_FILE" | grep "username:" | sed 's/.*username: *//; s/[\"'\'']//g' | tr -d '\r\n' | xargs)
export AZDATA_METRICSUI_PASSWORD=$(grep -A2 "metrics:" "$CREDS_FILE" | grep "password:" | sed 's/.*password: *//; s/[\"'\'']//g' | tr -d '\r\n' | xargs)
export AZDATA_USERNAME=$(grep -A1 "fallback:" "$CREDS_FILE" | grep "username:" | sed 's/.*username: *//; s/[\"'\'']//g' | tr -d '\r\n' | xargs)
export AZDATA_PASSWORD=$(grep -A2 "fallback:" "$CREDS_FILE" | grep "password:" | sed 's/.*password: *//; s/[\"'\'']//g' | tr -d '\r\n' | xargs)

echo "Credentials loaded from YAML file."
echo "  Logs UI User: $AZDATA_LOGSUI_USERNAME"
echo "  Metrics UI User: $AZDATA_METRICSUI_USERNAME"
echo "  Fallback User: $AZDATA_USERNAME"


# Create the Arc Data Services extension instance
echo "Creating Arc Data Services data controller..."

# Set extended timeout for Azure CLI to avoid premature timeout (default is typically 10-20 minutes)
export AZURE_CLI_CORE_TIMEOUT_IN_MINUTES=60
echo "Azure CLI timeout set to $AZURE_CLI_CORE_TIMEOUT_IN_MINUTES minutes"

az arcdata dc create \
    --name $extension_instance_name \
    --resource-group $arc_resource_group \
    --custom-location $customlocation_name \
    --cluster-name $arc_cluster_name \
    --connectivity-mode direct \
    --profile-name $arc_data_profile_name \
    --auto-upload-metrics true --auto-upload-logs true \
    --storage-class $storage_class \
    --infrastructure onpremises \
    --k8s-namespace $arc_data_namespace \
    --no-wait

echo ""
echo "Data controller creation initiated. Monitoring deployment progress..."
echo "This process can take 15-30 minutes depending on cluster resources and network speed."
echo ""

# Monitor the deployment progress using Azure CLI status command
timeout_minutes=60
timeout_seconds=$((timeout_minutes * 60))
start_time=$(date +%s)

while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    if [ $elapsed -gt $timeout_seconds ]; then
        echo "Monitoring timeout reached after $timeout_minutes minutes. Deployment may still be in progress."
        echo "Check status manually with: az arcdata dc status show -n $extension_instance_name -g $arc_resource_group --query properties.k8SRaw.status"
        break
    fi
    
    # Check data controller status using Azure CLI
    echo "Checking data controller status... (elapsed: $((elapsed / 60)) minutes)"
    dc_status=$(az arcdata dc status show -n $extension_instance_name -g $arc_resource_group --query properties.k8SRaw.status.state -o tsv 2>/dev/null || echo "")
    
    if [ -n "$dc_status" ]; then
        echo "Data controller status: $dc_status"
        
        if [ "$dc_status" = "Ready" ]; then
            echo "✅ Data controller deployment completed successfully!"
            echo ""
            echo "Final status:"
            az arcdata dc status show -n $extension_instance_name -g $arc_resource_group --query properties.k8SRaw.status
            break
        elif [ "$dc_status" = "Failed" ] || [ "$dc_status" = "Error" ]; then
            echo "❌ Data controller deployment failed!"
            echo "Full status details:"
            az arcdata dc status show -n $extension_instance_name -g $arc_resource_group --query properties.k8SRaw.status
            break
        fi
    else
        echo "Data controller not yet visible in Azure. Still initializing..."
    fi
    
    sleep 60  # Check every minute since Azure CLI calls are more expensive
done


# validate if custom location provisioned successfully
echo "Validating if the feature is enabled..."
az customlocation show -g $arc_resource_group -n $customlocation_name

echo ""
echo "Validating if the arc datacontroller is created..."
kubectl get datacontrollers -n $arc_data_namespace