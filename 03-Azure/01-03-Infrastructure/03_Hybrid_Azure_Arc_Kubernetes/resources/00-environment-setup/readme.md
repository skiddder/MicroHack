# Environment Setup
When working through the challenges of this microhack, it's assumed that you have an onprem k8s cluster available which you can use to arc-enable it. Also, it's assumed that you have a container registry, which you can use for the gitops challenge.

In this folder you find terraform code to deploy a k8s cluster and container registry in Azure for each participant of the microhack. It's intended that coaches create these resources for their participants before the microhack starts, so the participants can directly start with challenge 1 (onboarding/arc-enabling their cluster).

As a microhack coach, you will be given a subscription in the central microhack tenant. Terraform expects the subscription id within the azurerm provider. Therefore, you need to to create the provider.tf file in this folder. To achieve this, copy the provider-template.txt:

- Identify your subscription_id:
```bash
az account show --query id --output tsv
```

- Open the provider.tf file in your editor and replace "REPLACE-ME" string with the Azure subscription_id you want to deploy to.


- create a file called fixtures.tfvars. Open it in an editor an copy paste the following lines into it:
```terraform
client_id="WILL-BE-REPLACED-BY-SCRIPT"
client_secret="WILL-BE-REPLACED-BY-SCRIPT"
```
- run the script create_sp.sh to create a service principal which will be used by your AKS cluster. The scipt will fill in the client_id and secret to the fixtures.tfvars file.

- plan and deploy an AKS cluster which will simulate an on-prem Kubernetes cluster which will be used in the following challenge to arc-enable:
```bash
terraform plan -var-file=fixtures.tfvars -out=tfplan
terraform apply tfplan
``` 