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
In order to manage a namespace via flux, you need a repository. In this microhack we're using a public github repository. If using a private repo make sure to add credentials so flux is able to access your repository. The following command creates a flux configuration which watches the namespaces folder within this repository. All namespace definitions found in this folder will be applied to the cluster.
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
Copy itops.yaml and name it team1.yaml. Open it in your editor and change the labels.name and name values to "team1". Save the file and commit and push it. The flux configuration is configured to pull for changes every 10min. After 10min the new namespace will appear in your cluster.

#### Scenario 2 - Deploy an app using GitOps
In this microhack the focus is on automating deployment rather than on building the app. Therefore, we are not creating a full CI/CD pipeline at this point. Instead we will focus on how GitOps can be used to pull a new container version when your existing build pipeline has created and pushed it to your container repository.

We start by creating v1.0.0 of our demo hello-world app manually and push it to the existing Azure Container Registry of the microhack environment.
```bash
# use Azure Container Registry built-in function to create and push a container image to our registryssh 
acr_name=mharcaksacr

az acr build \
  --registry $acr_name \
  --image hello-world-flux:v1.0.0 \
  --file Dockerfile \
  .
```

Now, we are using the yaml deployment and service definitions located in folder '03-Azure/01-03-Infrastructure/03_Hybrid_Azure_Arc_Kubernetes/walkthrough/04-gitops/app-depl' to create a kustomization which will deploy the container. Please note there is also a file called kustomization.yaml in that folder which tells flux how to handle the deployment. Open the deployment.yaml in your editor, find the image definition on line 19 and change the repository name according to your Azure Container Registry name (i.e. 'mharck8sacr01'). Save the file. 

Use Azure CLI to tell Flux to sync this folder:
```bash
az k8s-configuration flux create \
  --resource-group $arc_resource_group \
  --cluster-name $arc_cluster_name \
  --cluster-type connectedClusters \
  --name flux-config-hello-world \
  --namespace hello-world \
  --scope cluster \
  --url https://github.com/skiddder/MicroHack \
  --branch main \
  --kustomization name=hello-world path=./03-Azure/01-03-Infrastructure/03_Hybrid_Azure_Arc_Kubernetes/walkthrough/04-gitops/app-depl prune=true interval=1m
```

When the kustomization has been applied, you can use kubectl to validate that the hello world app was deployed successfully:
```bash
kubectl get pods -n hello-world
kubectl get svc -n hello-world
```

### Resources
* [GitOps for Azure Kubernetes Service](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/gitops-aks/gitops-blueprint-aks)