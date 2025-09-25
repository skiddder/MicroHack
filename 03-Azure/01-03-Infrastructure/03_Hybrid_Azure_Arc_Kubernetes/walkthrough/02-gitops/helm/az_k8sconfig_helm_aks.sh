#!/bin/sh

# <--- Change the following environment variables according to your Azure service principal name --->

echo "Exporting environment variables"
export arc_resource_group='mh-arc-aks'
export arc_cluster_name='arc-enabled-K8s'
export cloned_app_repo='https://github.com/skiddder/azure-arc-jumpstart-apps'
export ingress_namespace='ingress-nginx'
export namespace='hello-arc'

# Create GitOps config for NGINX Ingress Controller
echo "Creating GitOps config for NGINX Ingress Controller"
az k8s-configuration flux create \
--cluster-name $arc_cluster_name \
--resource-group $arc_resource_group \
--name config-nginx \
--namespace $ingress_namespace \
--cluster-type connectedClusters \
--scope cluster \
--url $cloned_app_repo \
--branch main --sync-interval 3s \
--kustomization name=nginx prune=true path=./nginx/release

# Checking if Ingress Controller is ready
until kubectl get service/ingress-nginx-controller --namespace $ingressNamespace --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do echo "Waiting for NGINX Ingress controller external IP..." && sleep 20 ; done

# Create GitOps config for App Deployment
echo "Creating GitOps config for Hello-Arc App"
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
--kustomization name=app prune=true path=./hello-arc/releases/app sync_interval=3s retry_interval=20s

