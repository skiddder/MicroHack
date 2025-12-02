* open file az_connect_aks.sh in your editor
* check the export variable values. Make sure to match your environment. (i.e. in this microhack we assume that there is an AKS cluster simulating an onprem K8s cluster.)
* execute the script to
    * register required resource providers:
        * Microsoft.Kubernetes
        * Microsoft.KubernetesConfiguration
        * Microsoft.ExtendedLocation
    * merge the AKS credentials of the simulated onprem cluster into your kube.config file
    * remove Azure Arc helm charts which might exist from previous connection runs
    * install required Azure CLI extensions or update to latest version:
        * connectedk8s
        * k8s-configuration
    * connecting the simulated on-prem cluster to Azure Arc using the Azure CLI command
```bash
az connectedk8s connect --name $arc_cluster_name --resource-group $arc_resource_group --location $location --infrastructure 'azure' --distribution 'aks'
```
