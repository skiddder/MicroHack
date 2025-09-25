#!/bin/sh

#################################################################################################################
#                                                                                                               #
# NOTE: This script does not produce working configurations at the moment! Please use the helm charts instead!  #
#                                                                                                               #
#################################################################################################################

# <--- Change the following environment variables according to your Azure service principal name --->

echo "Exporting environment variables"
#export appId='<Your Azure service principal name>'
#export password='<Your Azure service principal password>'
#export tenantId='<Your Azure tenant ID>'
export arc_resource_group='mh-arc-aks'
export arc_cluster_name='arc-enabled-K8s'
export cloned_app_repo='https://github.com/skiddder/azure-arc-jumpstart-apps'
export namespace='hello-arc'

# Getting AKS credentials
#echo "Log in to Azure with Service Principal & Getting AKS credentials (kubeconfig)"
#az login --service-principal --username $appId --password=$password --tenant $tenantId
#az aks get-credentials --name $arcClusterName --resource-group $resourceGroup --overwrite-existing

# Create a namespace for your app & ingress resources
# kubectl create ns $namespace

# # Add the official stable repo
# helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
# helm repo update

# create a GitOps configuration referencing your repo
az k8s-configuration flux create \
--name cluster-config \
--cluster-name $arc_cluster_name \
--resource-group $arc_resource_group \
--url https://github.com/Azure/arc-k8s-demo \
--scope cluster \
--cluster-type connectedClusters

# TODO: Deploy the namespace via GitOps
# # Use Helm to deploy an NGINX ingress controller
# helm upgrade --install ingress-nginx ingress-nginx \
#   --repo https://kubernetes.github.io/ingress-nginx \
#   --namespace $namespace

echo "Creating namespaces for demo teams"
az k8s-configuration flux create \
--cluster-name $arc_cluster_name \
--resource-group $arc_resource_group \
--name cluster-baseline \
--namespace $namespace \
--cluster-type connectedClusters \
--scope cluster \
--url https://github.com/slack/cluster-config \
--branch main \
--sync-interval 3s \
--kustomization name=namespaces path=./namespaces


# TODO: jumpstartprod.azurecr.io/hello-arc:latest is no longer available, figure out alternative image
# Create GitOps config for Hello-Arc app
echo "Creating GitOps config for Hello-Arc app"
az k8s-configuration flux create \
--cluster-name $arc_cluster_name \
--resource-group $arc_resource_group \
--name config-helloarc \
--namespace $namespace \
--cluster-type connectedClusters \
--scope namespace \
--url $cloned_app_repo \
--branch main \
--sync-interval 3s \
--kustomization name=app path=./hello-arc/yaml

# Create GitOps config for Hello-Arc Ingress
echo "Creating GitOps config for Hello-Arc Ingress"
az k8s-configuration flux create \
--cluster-name $arc_cluster_name \
--resource-group $arc_resource_group \
--name config-helloarc-ingress \
--namespace $namespace \
--cluster-type connectedClusters \
--scope namespace \
--url $cloned_app_repo \
--branch main \
--kustomization name=app path=./hello-arc/ingress
