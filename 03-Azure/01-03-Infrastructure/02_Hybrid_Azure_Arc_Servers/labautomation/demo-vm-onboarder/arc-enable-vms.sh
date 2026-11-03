script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || exit 1

resourceGroupforOnprem="mh-arc-onprem"
resourceGroupforArc="mh-arc-cloud"
adminUsername="mhadmin"
adminPassword="REPLACE-ME"
arcRegion="westeurope"
triggerPolicyEvaluation=true

# the script takes about 1:30 min per VM

# create or tag the Arc resource group before onboarding
group_exists="$(az group exists --name "$resourceGroupforArc" --output tsv)" || exit $?
case "$group_exists" in
    true)
        group_id="$(az group show --name "$resourceGroupforArc" --query id --output tsv)" || exit $?
        if [ -z "$group_id" ]; then echo "Cannot read resource group ID for $resourceGroupforArc" >&2; exit 1; fi
        az tag update --resource-id "$group_id" --operation Merge --tags SecurityControl=Ignore || exit $?
        ;;
    false)
        az group create --name "$resourceGroupforArc" --location "$arcRegion" --tags SecurityControl=Ignore || exit $?
        ;;
    *)
        echo "Cannot determine whether resource group $resourceGroupforArc exists: $group_exists" >&2
        exit 1
        ;;
esac

#create service principal for arc onboarding
subscriptionId=$(az account show --query 'id' --output tsv)
tmp=$(az ad sp create-for-rbac --name "mh-arc-onboarding-sp" --role "Azure Connected Machine Onboarding" --scopes "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupforArc")
tenantId=$(echo $tmp | jq -r '.tenant')
servicePrincipalId=$(echo $tmp | jq -r '.appId')
clientSecret=$(echo $tmp | jq -r '.password')

######## set ansible variables according to target environment --> parameters will be passed on via ansible command line ########

for yamlFile in "$script_dir"/*.yml; do
  echo "Updating $yamlFile with service principal and resource group details"
  sed -i "s|service_principal_id: '.*'|service_principal_id: '$servicePrincipalId'|g" "$yamlFile"
  sed -i "s|service_principal_secret: '.*'|service_principal_secret: '$clientSecret'|g" "$yamlFile"
  sed -i "s|resource_group: '.*'|resource_group: '$resourceGroupforArc'|g" "$yamlFile"
  sed -i "s|tenant_id: '.*'|tenant_id: '$tenantId'|g" "$yamlFile"
  sed -i "s|subscription_id: '.*'|subscription_id: '$subscriptionId'|g" "$yamlFile"
  #sed -i "s|location: '.*'|location: '$LOCATION'|g" "$yamlFile"
done


# get all servers from the resource group where the onprem servers are mimicked
servers=$(az vm list -g $resourceGroupforOnprem | jq -c '.[]')

# Loop through each VM in the servers array
for server in $servers; do 
  vm_name=$(echo $server | jq -r '.name')
  vm_id=$(echo $server | jq -r '.id')
  public_ip=$(az vm list-ip-addresses --name "$vm_name" --resource-group "$resourceGroupforOnprem" --query "[].virtualMachine.network.publicIpAddresses[0].ipAddress" --output tsv)
  echo "Processing VM: $vm_name with ID: $vm_id"
  
  # Check if the current VM is a Windows OS
  os_type=$(echo $server | jq -r '.storageProfile.osDisk.osType')

  if [ "$os_type" == "Windows" ]; then
    echo "Starting Ansible playbook for Windows VM: $vm_name"
    ansible-playbook "$script_dir/onboard-win.yml" -i "$public_ip," -e "ansible_user='$adminUsername' ansible_password='$adminPassword' ansible_port=5985 ansible_connection=winrm ansible_winrm_transport=basic ansible_winrm_server_cert_validation=ignore" # azure_service_principal_id='$servicePrincipalId' azure_service_principal_secret='$clientSecret' azure_resource_group='$resourceGroupforArc' azure_tenant_id='$tenantId' azure_subscription_id='$subscriptionId'"
  else
    echo "Starting Ansible playbook for Linux VM: $vm_name"
    ansible-playbook "$script_dir/onboard-linux.yml" -i "$public_ip," -e "ansible_user='$adminUsername' ansible_ssh_pass='$adminPassword' ansible_port=22 ansible_connection=ssh ansible_ssh_common_args='-o StrictHostKeyChecking=no'" # azure_service_principal_id='$servicePrincipalId' azure_service_principal_secret='$clientSecret' azure_resource_group='$resourceGroupforArc' azure_tenant_id='$tenantId' azure_subscription_id='$subscriptionId'"
  fi

done

if [ "$triggerPolicyEvaluation" = true ]; then
  echo "Triggering policy evaluation for Azure Arc enabled servers"
  az policy state trigger-scan -g $resourceGroupforArc --no-wait
fi