#!/bin/bash

# Bootstrap script for complete K3s + Azure Arc deployment
# This script:
# 1. Deploys K3s cluster using Terraform
# 2. Connects the cluster to Azure Arc
# 3. Provides verification and status checks

set -e  # Exit on any error

echo "🚀 Starting complete K3s + Azure Arc bootstrap deployment"
echo "=================================================="

# Detect user information
azure_user=$(az account show --query user.name --output tsv)
user_number=$(echo $azure_user | sed -n 's/.*LabUser-\([0-9]\+\).*/\1/p')

if [ -z "$user_number" ]; then
    echo "❌ Error: Could not extract user number from Azure username: $azure_user"
    echo "Please make sure you're logged in as LabUser-XX"
    exit 1
fi

echo "✅ Detected user number: $user_number"
echo "📧 Azure user: $azure_user"

# Determine script locations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TERRAFORM_DIR="$LAB_DIR"
ARC_CONNECT_SCRIPT="$SCRIPT_DIR/az_connect_k8s.sh"

echo "📁 Working directories:"
echo "   Script dir: $SCRIPT_DIR"
echo "   Lab dir: $LAB_DIR" 
echo "   Terraform dir: $TERRAFORM_DIR"

# Validate prerequisites
echo ""
echo "🔍 Validating prerequisites..."

# Check if terraform is available
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed or not in PATH"
    exit 1
fi

# Check if terraform files exist
if [ ! -f "$TERRAFORM_DIR/main.tf" ]; then
    echo "❌ Terraform files not found in $TERRAFORM_DIR"
    exit 1
fi

# Check if Arc connection script exists
if [ ! -f "$ARC_CONNECT_SCRIPT" ]; then
    echo "❌ Arc connection script not found at $ARC_CONNECT_SCRIPT"
    exit 1
fi

echo "✅ All prerequisites validated"

# Change to terraform directory
cd "$TERRAFORM_DIR"

echo ""
echo "🏗️  Phase 1: Deploying K3s cluster with Terraform"
echo "================================================"

# Setup terraform provider with current subscription
subscription_id=$(az account show --query id --output tsv)
echo "📋 Using subscription ID: $subscription_id"

echo "🔧 Updating provider.tf with current subscription..."
sed -i "s|subscription_id = \".*\"|subscription_id = \"$subscription_id\"|" provider.tf

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "⚙️  Initializing Terraform..."
    terraform init
fi

# Plan and apply terraform
echo "📋 Creating Terraform plan..."
terraform plan -var-file=fixtures.tfvars -out=tfplan

echo "🚀 Applying Terraform deployment..."
terraform apply -parallelism=3 tfplan

# Verify deployment
echo "✅ Terraform deployment completed"

# Wait for VMs to be fully ready
echo "⏳ Waiting for VMs to be fully provisioned (60 seconds)..."
sleep 60

echo ""
echo "🔗 Phase 2: Connecting cluster to Azure Arc"
echo "============================================"

# Execute the Arc connection script
echo "🚀 Running Azure Arc connection script..."
bash "$ARC_CONNECT_SCRIPT"

echo ""
echo "🔍 Phase 3: Final verification and status"
echo "========================================="

# Additional verification steps
echo "📊 Cluster status:"
kubectl get nodes -o wide

echo ""
echo "🌐 Azure Arc status:"
az connectedk8s show --resource-group "${user_number}-k8s-arc" --name "${user_number}-k8s-arc-enabled" --query "{name:name, connectivityStatus:connectivityStatus, kubernetesVersion:kubernetesVersion}" -o table

echo ""
echo "🎉 Bootstrap deployment completed successfully!"
echo "=============================================="
echo ""
echo "📋 Summary:"
echo "   👤 User: $azure_user ($user_number)"
echo "   🏗️  On-premises RG: ${user_number}-k8s-onprem"
echo "   ☁️  Azure Arc RG: ${user_number}-k8s-arc"
echo "   🔗 Arc Cluster: ${user_number}-k8s-arc-enabled"
echo ""
echo "🌐 View your cluster in Azure Portal:"
echo "   https://portal.azure.com/#@/resource/subscriptions/$subscription_id/resourceGroups/${user_number}-k8s-arc/providers/Microsoft.Kubernetes/connectedClusters/${user_number}-k8s-arc-enabled"
echo ""
echo "💡 Next steps:"
echo "   • Your K3s cluster is now running and connected to Azure Arc"
echo "   • You can deploy Arc-enabled data services using the dataservice.sh script"
echo "   • Use kubectl commands to interact with your cluster"
echo "   • Explore Azure Arc features in the Azure Portal"
