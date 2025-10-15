### Prerequisites
* [helm](https://helm.sh/docs/intro/install/)
* Read and write permissions on the resource types
    * Microsoft.Kubernetes/connectedClusters 
    * Microsoft.ContainerService/managedClusters
    * Microsoft.KubernetesConfiguration/extensions
    * Microsoft.KubernetesConfiguration/fluxConfigurations
* Registration of the following Azure resource providers:
```bash
az provider register --namespace Microsoft.Kubernetes
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.KubernetesConfiguration
```
* Required cli extensions
```bash
az extension add -n k8s-configuration
az extension add -n k8s-extension
```
* Flux CLI installed #TODO: Is this required?
```bash
curl -s https://fluxcd.io/install.sh | sudo bash
```
* Extension microsoft.flux installed on your kubernetes cluster
```bash
export arc_resource_group='mh-arc-aks'
export arc_cluster_name='mh-arc-enabled-K8s'

az k8s-extension create \
  --name fluxExtension \
  --cluster-name $arc_cluster_name \
  --resource-group $arc_resource_group \
  --cluster-type connectedClusters \
  --extension-type microsoft.flux
```

### Solution
#### Scenario 1 - Manage cluster configuration using GitOps
```bash
repository="https://github.com/skiddder/MicroHack" #Change to your own fork of the Microhack repository
path="/03-Azure/01-03-Infrastructure/03_Hybrid_Azure_Arc_Kubernetes/walkthrough/04-gitops/namespaces"

az k8s-configuration flux create \
  --resource-group $arc_resource_group \
  --cluster-name $arc_cluster_name \
  --cluster-type connectedClusters \
  --name flux-config-namespace \
  --namespace flux-system \
  --scope cluster \
  --url $repository \
  --branch main \
  --kustomization name=namespace path=$path prune=true interval=1m
```
#### Scenario 2 - Build and deploy (CI/CD) apps using GitOps
### Resources
* [GitOps for Azure Kubernetes Service](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/gitops-aks/gitops-blueprint-aks) 