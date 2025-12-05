# Walkthrough Challenge 1 - Onboarding your Kubernetes Cluster
Duration: 20 minutes

[Home](../../Readme.md#challenge-1---onboarding-your-kubernetes-cluster) - [Next Challenge's Solution](../02-azure_monitor/solution.md)

## Prerequisites
Please ensure that you successfully verified the [general prerequisites](../../Readme.md#general-prerequisites) before starting this challenge.

## Task 1 - Login to Azure
In your shell environment, login to Azure using the account you got assigned during the microhack.
```bash
az logout # only required if you are logged in with another user from a previous session

az login # browser popup opens with credential prompt. Provide your user details and MFA as required
```

## Task 2 - Create Azure resource group
Next you will need to create a resource group where the arc-enabled-k8s resource will be created. Please use the postfix which matches your microhack user account - i.e. exchange the "01" with "04" if you are user04. 
```bash
az group create --name mh-arc-k8s-01 --location westeurope
```


## Task 3 - Connect K8s cluster using script
* Open file az_connect_aks.sh in your editor - i.e. in Visual Studio Code. You can find the file in the microhack repo in the folder '03-Azure/01-03-Infrastructure/03_Hybrid_Azure_Arc_Kubernetes/walkthrough/01-connect'
* Check the export variable values and adjust the values to match your environment (i.e. replace "01" with "04" if you are user04) and save your changes. 
```bash
# adjust the postfix according to your microhack user number
export onprem_aks_cluster_name='01-onprem-k8s'  
export onprem_resource_group='mh-01-arc-k8s-onprem'
export arc_resource_group='mh-01-arc-k8s'
export arc_cluster_name='01-arc-enabled-k8s'
```
* Execute the script to
    * register required resource providers:
        * Microsoft.Kubernetes
        * Microsoft.KubernetesConfiguration
        * Microsoft.ExtendedLocation
    * merge the AKS credentials of the onprem cluster into your kube.config file
    * remove Azure Arc helm charts which might exist from previous connection attempts
    * install required Azure CLI extensions or update them to latest version:
        * connectedk8s
        * k8s-configuration
    * connecting the simulated onprem cluster to Azure Arc using the Azure CLI approach
```bash
./az_connect_aks.sh 
```
You successfully completed challenge 1! 🚀🚀🚀

[Back to the challenges](../../Readme.md#challenge-2---configure-gitops-for-cluster-management)