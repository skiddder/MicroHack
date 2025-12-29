# Walkthrough Challenge 4 - Deploy SQL Managed Instance to your cluster

[Back to challenge](../../challenges/challenge-04.md) - [Next Challenge's Solution](../challenge-05/solution.md)

## prerequisites
- [client tools](https://learn.microsoft.com/en-us/azure/azure-arc/data/install-client-tools)
- Provider reqistration
```shell
az provider register --namespace Microsoft.AzureArcData
```

## Read about the prerequisites and concepts
1. Create Azure Arc [data services cluster extension](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/conceptual-extensions)
2. Create a [custom location] on your arc-enabled k8s(https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/custom-locations#create-custom-location)
3. create the Arc data controller

## Create arc data services controller
Open the file '01-enable-dataservice.sh' in your editor.

Get a list of available storage profiles by running the CLI command below. Pick an appropriate storage profile for your environment. In this microhack, you need to choose one of the aks profiles.
```bash
az arcdata dc config list
```
To check the details of a given profile, export the profile locally for inspection:
```bash
# example - adjust --source value to view other profiles
az arcdata dc config init --source azure-arc-aks-default-storage --path ./arcdata-profile
```
Adjust the parameters in the beginning of the script to reflect your environment:
```bash
export arc_resource_group='mh-arc-aks'
export arc_cluster_name='mh-arc-enabled-K8s'
export customlocation_name='onprem-aks-cl'       # <-- you can change this according to your naming convention
export extensionInstanceName="arc-data-services" # <-- you can change this according to your naming convention
export arc_data_namespace="arc-data-controller"  # <-- you can change this according to your naming convention
export arc_data_profile_name='azure-arc-aks-default-storage'
```
Save the file and run it. During script execution you will be prompted for some parameters:

| Parameter | Example | Description | 
|-----------|---------|-------------|
| Log Analytics workspace ID | xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | Provide just the guid, not the full path of the resource. You can copy it in the Azure Portal from your Log Analytics workspace from Settings > Agents > Log Analytics agents instructions.  |
| Log Analytics primary key  | adjf23nadfSAFSAh32j23jksjj223LKasdf== | base64 encoded string. You can copy it in the Azure Portal from your Log Analytics workspace from Settings > Agents > Log Analytics agents instructions. |
| Monitoring administrator username | john-doe | Used to access your grafana dashboard if configured |
| Monitoring administrator password | P@ssW0rd | Passwords must be at least 8 characters long, cannot contain the username, and must contain characters from three of the following four sets: Uppercase letters, Lowercase letters, Base 10 digits, and Symbols. Please try again. |

When the script finishes, the kubernetes cluster should be ready to host arc-enabled data services such as SQL MI and PostgreSQL.

## Read about SQL Managed Instance concepts
* [Deploy a SQL Managed Instance enabled by Azure Arc](https://learn.microsoft.com/en-us/azure/azure-arc/data/create-sql-managed-instance)

## Create SQL Managed Instance in connected cluster

Open file '02-create-sql-mi.sh' in your editor. Adjust parameters to reflect your environment, save and execute the script. During script execution you will be prompted for required parameters

| Parameter | Example | Description |
|-----------|---------|-------------|
| SQL Managed Instance admin username | sa | sql admin account |
| SQL Managed Instance admin password | P@ssW0rd | password for the admin account |

Now, it's time to grab a coffee as the creation will take several minutes.

## Connect to your SQL Managed Instance

You successfully completed challenge 1! 🚀🚀🚀

[Next challenge](../../challenges/challenge-05.md) - [Next Challenge's Solution](../challenge-05/solution.md)