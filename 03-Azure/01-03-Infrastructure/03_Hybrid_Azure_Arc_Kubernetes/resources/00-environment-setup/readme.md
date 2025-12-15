# Environment Setup
When working through the challenges of this microhack, it's assumed that you have an onprem k8s cluster available which you can use to arc-enable it. Also, it's assumed that you have a container registry, which you can use for the gitops challenge.

In this folder you find terraform code to deploy a k8s cluster and container registry in Azure for each participant of the microhack. It's intended that coaches create these resources for their participants before the microhack starts, so the participants can directly start with challenge 1 (onboarding/arc-enabling their cluster).

## Resources to be deployed
2 resource groups, 1 k8s cluster, 1 container registry per participant where xy represents the participant number:
```
subscription
|
├── <xy>-k8s-arc (resource group)
|   |
│   └── <xy>mhacr (container registry)
|   |
|   └── <xy>-law (log analytics workspace)
|
└── <xy>-k8s-onprem (resource group)
    |
    └── <xy>-k8s-onprem (k8s cluster)
```

## Prerequisites
* bash shell (tested with Ubuntu 22.04)
* Azure CLI
* terraform
* clone this repo locally, so you can adjust the deployment files according to your needs
* Azure subscription
* User account with subscription owner permissions
* Sufficient quota limits to support creation of k8s clusters per participant 

If you don't change the default value of parameter "vm_size" in variables.tf two Standard_D4as_v5 VMs per cluster are used as worker nodes. If you have many participants you need to ensure that the quota limit in your subscription is sufficient to support the required cores. The terraform code will distribute the k8s clusters to 10 different regions. This setting can be adjusted via the parameter "onprem_resources" (variables.tf) value.

You can check this limit via Azure Portal (subscription > settings > Usage & Quotas):

![alt text](img/image.png)



## Installation instructions
As a microhack coach, you will be given a subscription in the central microhack tenant. Terraform expects the subscription id within the azurerm provider. Therefore, you need to to create the provider.tf file in this folder. To achieve this

* copy the provider-template.txt and rename the copy to 'provider.tf'.

The terraform code deploys AKS clusters which will be used as onprem k8s clusters. We chose this approach because the deployment automation is easier than using another distribution. We are aware of course, that in an AKS cluster it does not make sense to arc-enable it as all arc features are available natively already.

The AKS deployment requires a service principal which represents the cluser's identity. We will use the same service principal for all clusters which are created by this terraform code.

* Create a file called fixtures.tfvars. Open it in an editor an copy paste the following lines into it:
```terraform
client_id="WILL-BE-REPLACED-BY-SCRIPT"
client_secret="WILL-BE-REPLACED-BY-SCRIPT"
```

* Now, run the script create_sp.sh to create a new service principal. The script will fill in the client_id and secret to the fixtures.tfvars file automatically. It will also set the subscription id within the provider.tf file.

```bash
az logout # only required if you have been logged in with another account
az login  # use the subscription owner account you received as coach from your central microhack tenant

 sudo chmod +x ./create_sp.sh # add execution permissions on the script file of not yet done

./create_sp.sh
```
Validate that provider.tf and fixtures.tfvars are using the correct values.

* Open the variables.tf file in your editor. Locate the variables start_index and end_index. All resources which are created by this terraform code will get a two-digit numeric prefix. It's intended that each user easily finds "his" resources. If a user i.e. got assigned the account "LabUser-37" he should work with the resources with the prefix "37". The central microhack team precreates the user accounts and assigns them to the different microhacks (which ususally run in parallel on the same day). So the users probably do not start with "01". Depending on what user accounts you got provided, you can use these parameters to adjust the prefixes to match your user numbers. Example: You receive the users LabUser-50 to LabUser-59, set the start_index value to 50 and the end_index value to 59. Make sure you saved your changes.

```terraform
variable "start_index" {
  description = "Starting index for resource naming"
  type        = number
  default     = 37
}

variable "end_index" {
  description = "Ending index for resource naming"
  type        = number
  default     = 39
}
```

* Execute terraform plan and apply. Make sure to include your fixtures.tfvars file.
```bash
terraform init # download terraform providers

terraform plan -var-file=fixtures.tfvars -out=tfplan

# have a look at the resources which will be created. There should be two resource groups per participant as well as an AKS cluster and an Azure container registry.
# after validation:

terraform apply tfplan
``` 
The expected output looks approximatley like this depending on the start_index and end_index parameters:
```bash
acr_names = {
  "37" = "37mhacr"
  "38" = "38mhacr"
}
onprem_k8s_name = {
  "37" = "37-k8s-onprem"
  "38" = "38-k8s-onprem"
}
rg_names_arc = {
  "37" = "37-k8s-arc"
  "38" = "38-k8s-arc"
}
rg_names_onprem = {
  "37" = "37-k8s-onprem"
  "38" = "38-k8s-onprem"
}
```

TODO: Add resource deletion instructions...

[Back to the challenges](../../Readme.md#challenge-1---onboarding-your-kubernetes-cluster)
