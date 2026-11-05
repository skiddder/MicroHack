# Walkthrough Challenge 1 - Onboarding your Kubernetes Cluster
Duration: 15-30 minutes

## Prerequisites
For Hackbox Console labs, first [connect to your workstation](#connect-to-your-workstation-hackbox-console).
Use the **On-prem Resource Group**, **Arc Resource Group** and shared Bastion shown in your
dashboard, not the numeric resource group names in the manual fallback examples below.

Please ensure that you successfully verified 
* the [general prerequisites](../../Readme.md#general-prerequisites) before starting this challenge.
* that you can see your two resource groups in the [Azure portal](https://portal.azure.com). Use the names from the HB Console; for the manual fallback, LabUser-37 uses "37-k8s-arc" and "37-k8s-onprem".
* that you can successfully connect to all [required Azure endpoints](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/network-requirements?tabs=azure-cloud)

💡*Hint*: There are several connectivity-check scripts available [here](../../lab/scripts/).

## Connect to your workstation (Hackbox Console)

1. Wait until your deployment has completed successfully. In the **HB Console**, open
   your lab's **Credentials** and locate:

   | Credential | Purpose |
   | --- | --- |
   | **Workstation VM** | Your Windows VM, for example `labuser-0020` |
   | **On-prem Resource Group** | The VM's resource group, for example `rg-labuser-0020-onprem` |
   | **VM Admin Username** / **VM Admin Password** | Credentials for signing in to Windows |
   | **Bastion Name** / **Bastion Resource Group** | The shared Bastion used to access your VM |

2. Sign in to the [Azure portal](https://portal.azure.com) with your assigned
   **LabUser Azure account**. These are your Azure account credentials, not the VM
   administrator credentials.
3. Open the **On-prem Resource Group**, select your **Workstation VM**, then select
   **Connect > Bastion**. Use the existing shared Bastion identified in the HB Console;
   do **not** create another Bastion or assign a public IP to the VM.
4. Connect using **RDP**, port **3389**, and **VM Password** authentication. Enter
   **VM Admin Username** (normally `mhadmin`) and **VM Admin Password** exactly as
   shown in the HB Console. Do not use your LabUser Azure password here.
5. Select **Connect** to open the Windows desktop in your browser. Allow pop-ups for
   the Azure portal if the session opens in a new tab.
6. On the workstation, open **Windows Terminal** and select the **Ubuntu** profile.
   Alternatively, run `wsl -d Ubuntu` from PowerShell. Run the following in this
   **Ubuntu/WSL shell**, not in PowerShell or Azure Cloud Shell:

   ```bash
   lsb_release -a
   ```
   Expected output is something like this:
   ```bash
   No LSB modules are available.
   Distributor ID: Ubuntu
   Description:    Ubuntu 26.04.1 LTS
   Release:        26.04
   Codename:       resolute
   ```

Continue with Task 1 below in the same WSL session. For challenges 2-5, keep using
this session or run `source ~/.microhack-k8s.env` again.

## Task 1 - Login to Azure
In your workstation's Ubuntu/WSL shell, login to Azure using the account you got assigned during the microhack.
```bash
az logout # only required if you are logged in with another user from a previous session

az login # Sign in with your assigned LabUser Azure account, not the VM administrator account
```
In case you are prompted to select a subscription, please do so. In the microhack environment you just can hit enter as you only have one subscription available.

Validate that you can see the **Arc Resource Group** and **On-prem Resource Group**
listed in your **HB Console Credentials** in the [Azure portal](https://portal.azure.com).
For example, `labuser-0020` uses `rg-labuser-0020` and `rg-labuser-0020-onprem`.
Open your **On-prem Resource Group**. There should be four VMs (master, worker1,
worker2 and workstation). The workstation is named `labuser-0020` in this example;
the K3s node names still use a generated prefix. Make sure that all VMs are running.
![img-start-vm](img/vm-start.png)

In the Bash block below, replace the placeholders with **VM Admin Username** and
**On-prem Resource Group** from your **HB Console Credentials**. When `scp` prompts
for a password, enter **VM Admin Password**, not your LabUser Azure password.
The script discovers the master VM in your on-prem RG, copies its kubeconfig into
`~/.kube/config` and then checks the cluster connection.

For the manual Terraform fallback, use the administrator username provided by your
coach and your original on-prem RG name (for example `37-k8s-onprem`) instead.

```bash
# Replace these values with the corresponding HB Console Credentials
admin_user="<VM Admin Username>"
onprem_resource_group="<On-prem Resource Group>"

# Discover the master VM without assuming a LabUser-based node name
master_vm_name=$(az vm list --resource-group "$onprem_resource_group" --query "[?ends_with(name, '-k8s-master')].name | [0]" --output tsv)
master_ip=$(az vm show --resource-group "$onprem_resource_group" --name "$master_vm_name" --show-details --query privateIps --output tsv)
scp_port=""

# ── Optional: only if working from your LOCAL machine instead of the workstation VM ──
# Uncomment and fill in the shared Bastion credentials from the HB Console:
# bastion_name="<Bastion Name>"
# bastion_resource_group="<Bastion Resource Group>"
# master_vm_id=$(az vm show --resource-group "$onprem_resource_group" --name "$master_vm_name" --query id --output tsv)
# az network bastion tunnel --name "$bastion_name" --resource-group "$bastion_resource_group" --target-resource-id "$master_vm_id" --resource-port 22 --port 2222 &
# az network bastion tunnel --name "$bastion_name" --resource-group "$bastion_resource_group" --target-resource-id "$master_vm_id" --resource-port 6443 --port 6443 &
# sleep 5 ; master_ip="127.0.0.1" ; scp_port="-P 2222"
# ── End optional block ──

# Create .kube directory if it doesn't exist
mkdir -p ~/.kube

# Copy the kubeconfig to standard location
scp ${scp_port:-} "$admin_user@$master_ip:~/.kube/config" ~/.kube/config
chmod 600 ~/.kube/config

# Replace localhost address with the master IP
sed -i "s/127.0.0.1/$master_ip/g" ~/.kube/config

# Now kubectl works directly — no need to ssh into the master node anymore
kubectl get nodes
```

💡 **How does this work?** From the workstation VM, `master_ip` is the private IP and all traffic stays on the VNet. If the optional block is uncommented, `master_ip` is overridden to `127.0.0.1` — SCP goes through the SSH tunnel (port 2222) and the sed becomes a no-op, so `kubectl` talks to `127.0.0.1:6443` through the K3s API tunnel.

All three Kubernetes nodes should now report **Ready**. Only then continue with Task 2.

Expected output is something similar to this:
```bash
NAME                          STATUS   ROLES                       AGE    VERSION
k8s7bbc1170d029-k8s-master    Ready    control-plane,etcd,master   151m   v1.33.6+k3s1
k8s7bbc1170d029-k8s-worker1   Ready    <none>                      147m   v1.33.6+k3s1
k8s7bbc1170d029-k8s-worker2   Ready    <none>                      148m   v1.33.6+k3s1
```

## Task 2 - Connect K8s cluster using script

The script loads `~/.microhack-k8s.env` when available. Without that file, it
checks for the actual HB exercise RG using your complete Azure account name:
`labuser-0009` maps to `rg-labuser-0009`, with `rg-labuser-0009-onprem` for the
VMs. Leading zeros are preserved. The master VM supplies the default Arc cluster
prefix, and the exercise RG supplies the region. The old numeric RG names are
used only when the corresponding Terraform fallback exercise RG actually exists.
Explicitly supplied environment values take precedence.

* In your shell go to your home folder
* Clone the microhack repo so you have the scripts locally on this machine 
* Change to the sub-folder '03-Azure/01-03-Infrastructure/03_Hybrid_Azure_Arc_Kubernetes/walkthrough/challenge-01'
* Execute the script to
    * register required resource providers in your subscription (this step may take several minutes if the resource providers have not been registered before):
        * Microsoft.Kubernetes
        * Microsoft.KubernetesConfiguration
        * Microsoft.ExtendedLocation
    * remove Azure Arc helm charts which might exist from previous connection attempts
    * install required Azure CLI extensions or update them to latest version:
        * connectedk8s
        * k8s-configuration
    * connecting the simulated onprem cluster to Azure Arc using the Azure CLI approach

💡 *Important*: Make sure that your kubectl works and is pointing to the k8s cluster you want to onboard before executing the script!

💡 *WSL users*: Clone to a native Linux path (e.g. `~`), **not** to `/mnt/c/...`. The Windows NTFS mount does not support POSIX file permissions and `git clone` will fail there.

```bash
# Clone only the Arc Kubernetes microhack using sparse-checkout
cd ~
git clone --depth 1 --filter=blob:none --sparse https://github.com/microsoft/MicroHack.git
cd MicroHack

git sparse-checkout set 03-Azure/01-03-Infrastructure/03_Hybrid_Azure_Arc_Kubernetes
cd 03-Azure/01-03-Infrastructure/03_Hybrid_Azure_Arc_Kubernetes/walkthrough/challenge-01

# Make the script executable and run it
chmod +x az_connect_k8s.sh
./az_connect_k8s.sh 
```

Wait until the script terminates. Expected result should look comparable to this output:
```bash
Exporting environment variables
Registering Azure Arc providers
Namespace             RegistrationPolicy    RegistrationState
--------------------  --------------------  -------------------
Microsoft.Kubernetes  RegistrationRequired  Registered
Namespace                          RegistrationPolicy    RegistrationState
---------------------------------  --------------------  -------------------
Microsoft.KubernetesConfiguration  RegistrationRequired  Registered
Namespace                   RegistrationPolicy    RegistrationState
--------------------------  --------------------  -------------------
Microsoft.ExtendedLocation  RegistrationRequired  Registered
Getting AKS credentials (kubeconfig)
Merged "37-k8s-onprem" as current context in /home/simon/.kube/config
Clear cached helm Azure Arc Helm Charts
Checking if you have up-to-date Azure Arc AZ CLI 'connectedk8s' extension...
Latest version of 'connectedk8s' is already installed.

Use --debug for more information

Checking if you have up-to-date Azure Arc AZ CLI 'k8s-configuration' extension...
Latest version of 'k8s-configuration' is already installed.

Use --debug for more information

Connecting the cluster to Azure Arc
This operation might take a while...

Step: 2025-12-12T14-32-41Z: Validating custom access token
Step: 2025-12-12T14-32-41Z: Checking Provider Registrations
Step: 2025-12-12T14-32-42Z: Setting KubeConfig
Step: 2025-12-12T14-32-42Z: Escape Proxy Settings, if passed in
Step: 2025-12-12T14-32-42Z: Checking Connectivity to Cluster
Step: 2025-12-12T14-32-43Z: Do node validations
Step: 2025-12-12T14-32-43Z: Install Kubectl client if it does not exist
Step: 2025-12-12T14-32-43Z: Install Helm client if it does not exist
Step: 2025-12-12T14-32-43Z: Starting Pre-onboarding-check
Step: 2025-12-12T14-32-43Z: Creating folder for Cluster Diagnostic Checks Logs
Step: 2025-12-12T14-32-43Z: Get namespace of release: cluster-diagnostic-checks
Step: 2025-12-12T14-32-44Z: Determine Helmchart Export Path
Step: 2025-12-12T14-32-44Z: Pulling HelmChart: mcr.microsoft.com/azurearck8s/helmchart/stable/clusterdiagnosticchecks, Version: 1.31.2
Step: 2025-12-12T14-32-46Z: Chart path for Cluster Diagnostic Checks Job: /home/simon/.azure/PreOnboardingChecksCharts/clusterdiagnosticchecks
Step: 2025-12-12T14-32-46Z: Creating Cluster Diagnostic Checks job
Step: 2025-12-12T14-32-59Z: The required pre-checks for onboarding have succeeded.
Step: 2025-12-12T14-32-59Z: Checking if user can create ClusterRoleBindings
Step: 2025-12-12T14-32-59Z: Determining Cluster Distribution and Infrastructure
Connecting an Azure Kubernetes Service (AKS) cluster to Azure Arc is only required for running Arc enabled services like App Services and Data Services on the cluster. Other features like Azure Monitor and Azure Defender are natively available on AKS. Learn more at https://go.microsoft.com/fwlink/?linkid=2144200.
Step: 2025-12-12T14-32-59Z: Checking Connect RP is available in the Location passed in.
Step: 2025-12-12T14-32-59Z: Check if an earlier azure-arc release exists
Step: 2025-12-12T14-32-59Z: Get namespace of release: azure-arc
Step: 2025-12-12T14-33-01Z: Deleting Arc CRDs
Step: 2025-12-12T14-33-09Z: Check if ResourceGroup exists.  Try to create if it doesn't
Step: 2025-12-12T14-33-09Z: Generating Public-Private Key pair
Step: 2025-12-12T14-33-14Z: Generating ARM Request Payload
Step: 2025-12-12T14-33-14Z: Azure resource provisioning has begun.
Step: 2025-12-12T14-34-49Z: Checking Custom Location(Microsoft.ExtendedLocation) RP Registration state for this Subscription, and attempt to get the Custom Location Object ID (OID),if registered
Step: 2025-12-12T14-34-52Z: Azure resource provisioning has finished.
Step: 2025-12-12T14-34-53Z: Determine Helmchart Export Path
Step: 2025-12-12T14-34-53Z: Pulling HelmChart: mcr.microsoft.com/azurearck8s/batch1/stable/v2/azure-arc-k8sagents, Version: 1.31.3
Step: 2025-12-12T14-34-55Z: Starting to install Azure arc agents on the Kubernetes cluster.
{
  "aadProfile": {
    "adminGroupObjectIDs": null,
    "tenantId": null
  },
  [...]
    "arcAgentProfile": {
    "agentAutoUpgrade": "Enabled",
    "agentErrors": null,
    "agentState": null,
    "desiredAgentVersion": null,
    "systemComponents": null
  },
  "arcAgentryConfigurations": null,
  "azureHybridBenefit": "NotApplicable",
  "connectivityStatus": "Connecting",
  "distribution": "k3s",
  "distributionVersion": null,
  "gateway": null,
  [...]
  "location": "westeurope",
  "managedIdentityCertificateExpirationTime": null,
  "miscellaneousProperties": null,
  "name": "37-k8s-arc-enabled",
  "offering": null,
  "oidcIssuerProfile": null,
  "privateLinkScopeResourceId": null,
  "privateLinkState": "Disabled",
  "provisioningState": "Succeeded",
  "resourceGroup": "37-k8s-arc",
  "securityProfile": null,
  [...]
  "tags": {},
  "totalCoreCount": null,
  "totalNodeCount": null,
  "type": "microsoft.kubernetes/connectedclusters"
}
```
In the [Azure portal](https://portal.azure.com) type 'Azure Arc' into the search bar at the top of the page. In the results in section 'Services' click 'Azure Arc'.
In the Azure Arc page in the left navigation pane, open the 'infrastucture' section and click 'Kubernetes clusters'.
You should see your resource of type 'Kubernetes - Azure Arc'. (i.e. if you are LabUser-37 you should see a resource named '37-k8s-arc-enabled'). Click on the name of the resource matching your user number.

Notice the Arc Agent version in the overview page.

In the navigation pane in section 'Kubernetes resources' click on 'Namespaces'. You will see a prompt to provide an access token:

![access-token](img/access-token.png)

In order to get access to the k8s resources from the Azure portal assign your entra user a clusterRoleBinding with appropriate permissions:
```bash
# get the user principal from entra
azure_user=$(az ad signed-in-user show --query userPrincipalName -o tsv)

# create a clusterRoleBinding for the user
kubectl create clusterrolebinding demo-user-binding --clusterrole cluster-admin --user=$azure_user

```
Now, reload the resources page in the Azure portl. You should see at least the following namespaces:

![img-namespaces](img/namespaces.png)

You successfully completed challenge 1! 🚀🚀🚀

[Next challenge](../../challenges/challenge-02.md) - [Next Challenge's Solution](../challenge-02/solution-02.md)