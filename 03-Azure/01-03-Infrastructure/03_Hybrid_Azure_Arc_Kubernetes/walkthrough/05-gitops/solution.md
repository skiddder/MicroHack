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
export acr_name=mharcaksacr

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
Take not of the public IP address returned for the hello-world-service. Copy and paste it to your browser. You should get a page with the text: 'Hello, World from Flux!'.

Until this point we have just deployed a pod using a fixed container image version. If we want to automatically update new images in the cluster when they get pushed to the container registry, we need to add 3 Flux Image Automation resources along with secrets to allow flux to pull images and to write to git.

##### GitHub PAT
*Please note*: We will use the user which forked the repository (you!) in this microhack. Please note that in production scenarios you would rather create a dedicated "bot" user for this purpose.

In GitHub ➜ Settings ➜ Developer settings ➜ Personal access tokens ➜ Fine‑grained tokens ➜ Generate new:

* Resource owner: your org / user that owns the repo
* Repository access: Only select repositories ➜ pick the repo Flux will update
* Permissions (Repository):
  * Token name: flux-agent
  * Description: for arc-enabled-k8s microhack
  * Repository access: Only select repos (select your fork of this repo)
  * Permissions: Select Contents 
    * Read and write (required for committing)
    * Metadata: Read (implicit)
  * (Nothing else needed)

Save the token somewhere safe for the next command.

*Least‑privilege tip*: scope it to just the one repo; set a reasonable expiration and plan for rotation.

Create the kubernetes secret for flux. Change the github-username accordingly and replace the place holder <fine-grained-pat> with the token value from the previous step:
```bash
kubectl -n flux-system create secret generic git-writer-creds \
  --from-literal=username=<github-username-or-bot> \
  --from-literal=password=<fine-grained-PAT>
```

##### ACR pull secret
*Please note*: In this microhack we will use the ACR admin user. In a real world scenario we recommend using a service principal for pulling from the ACR.

```bash
# set the container registry to enable admin user credentials next to RBAC
az acr update -n $acr_name --admin-enabled true

ADMIN_USER=$(az acr show -n $acr_name --query "adminUserEnabled" -o tsv) # should be 'true'
echo $ADMIN_USER

# retrieve user name and password of container registry
USERNAME=$(az acr credential show -n $acr_name --query "username" -o tsv)
PASSWORD=$(az acr credential show -n $acr_name --query "passwords[0].value" -o tsv)

# create a secret in kubernetes for flux to pull images
kubectl -n hello-world create secret docker-registry acr-pull-creds \
  --docker-server=$acr_name.azurecr.io \
  --docker-username="$USERNAME" \
  --docker-password="$PASSWORD"
```
*Least-privilege tip*: Admin user is registry‑wide and long‑lived. Prefer a scoped SP with RABC for production.

##### Flux Image Automation

Have a look at folder 'clusters/my-cluster/image-automation'. It contains four yaml files which are required for the image-automation to function.
* imagepolicy.yaml
* imagerepository.yaml
* imageupdateautomation.yaml
* kustomization.yaml
Optionally, you can check the existing flux setup:
```bash
# List Flux configurations pointing to your github repo
kubectl -n flux-system get gitrepositories.source.toolkit.fluxcd.io
```
Make sure that the gitrepository name matches the name in the imageautomation.yaml:
```yaml
spec:
  interval: 1m
  sourceRef:
    kind: GitRepository
    name: flux-config-namespace        # <-- MUST equal your existing GitRepository CR name defined in your Kustomization, NOT ImageRepository
    namespace: flux-system  
```

In order for the image automation kustomization to work, we need to change the existing 'app-depl/deployment.yaml' so flux knows where and how to update the image in the deployment manifest (note the comment in spec.containers.image):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-world
  namespace: hello-world
  labels:
    app: hello-world
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello-world
  template:
    metadata:
      labels:
        app: hello-world
    spec:
      containers:
      - name: hello-world
        image: mharcaksacr.azurecr.io/hello-world-flux:v1.0.0 # {"$imagepolicy": "hello-world:hello-world-policy"}
        ports:
        - containerPort: 8080
```
Save, commit and push your changes.

Now we are ready to create the new image-automation kustomization using Azure CLI:
```bash
az k8s-configuration flux create \
  --resource-group $arc_resource_group \
  --cluster-name $arc_cluster_name \
  --cluster-type connectedClusters \
  --name flux-config-image-automation \
  --namespace hello-world \
  --scope cluster \
  --url https://github.com/skiddder/MicroHack \
  --branch main \
  --kustomization name=image-automation path=./03-Azure/01-03-Infrastructure/03_Hybrid_Azure_Arc_Kubernetes/walkthrough/04-gitops/clusters/my-cluster/image-automation prune=true interval=1m
```

Last thing is to update the existing kustomization for our hello-world app:
```bash
# identify the existing kustomization name
az k8s-configuration flux list   --resource-group $arc_resource_group   --cluster-name $arc_cluster_name   --cluster-type connectedClusters   -o table

# expected output (in the example below it's "hello-world")
Namespace    Name                     Scope    ProvisioningState    ComplianceState    StatusUpdatedAt                   SourceUpdatedAt
-----------  -----------------------  -------  -------------------  -----------------  --------------------------------  -------------------------
hello-world  flux-config-hello-world  cluster  Succeeded            Compliant          2025-10-30T11:11:41.423000+00:00  2025-10-30T09:35:17+00:00
flux-system  flux-config-namespace    cluster  Succeeded            Compliant          2025-10-30T11:11:41.425000+00:00  2025-10-30T09:35:17+00:00

# Validate that the path is pointing to the correct folder
az k8s-configuration flux kustomization list --name flux-config-hello-world  --resource-group $arc_resource_group   --cluster-name $arc_cluster_name   --cluster-type connectedClusters   -o table

# example output
Name         Path                                                                                           DependsOn    SyncInterval    Timeout    Prune    Force
-----------  ---------------------------------------------------------------------------------------------  -----------  --------------  ---------  -------  -------
hello-world  ./03-Azure/01-03-Infrastructure/03_Hybrid_Azure_Arc_Kubernetes/walkthrough/04-gitops/app-depl               1m              10m        True     False

# update hello-world app kustomization
az k8s-configuration flux kustomization update \
  --resource-group $arc_resource_group \
  --cluster-name $arc_cluster_name \
  --cluster-type connectedClusters \
  --flux-configuration-name flux-config-namespace \
  --name flux-config-hello-world \
  --depends-on image-automation
```

### Resources
* [GitOps for Azure Kubernetes Service](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/gitops-aks/gitops-blueprint-aks)