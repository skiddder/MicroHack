# Walkthrough Challenge 1 - Onboarding your Kubernetes Cluster
Duration: 20 minutes

[Home](../../Readme.md#challenge-1---onboarding-your-kubernetes-cluster) - [Next Challenge's Solution](../02-azure_monitor/solution.md)

## Prerequisites
Please ensure that you successfully verified the [general prerequisites](../../Readme.md#general-prerequisites) before starting this challenge.

## Task 1 - Create Azure resource group
## Task 2 - Connect K8s cluster using script
* Open file az_connect_aks.sh in your editor
* Check the export variable values and adjust the values to match your environment and save your changes. 
```bash
# adjust the postfix according to your microhack user number
export onprem_aks_cluster_name='onprem-k8s-01'  
export onprem_resource_group='mh-arc-k8s-onprem-01'
export arc_resource_group='mh-arc-k8s-01'
export arc_cluster_name='mh-arc-enabled-k8s-01'
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