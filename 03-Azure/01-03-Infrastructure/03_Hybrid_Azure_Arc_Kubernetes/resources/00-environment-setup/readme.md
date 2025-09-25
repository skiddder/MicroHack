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