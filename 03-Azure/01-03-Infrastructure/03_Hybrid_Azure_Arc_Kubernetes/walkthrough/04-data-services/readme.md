## prerequisites
- [client tools](https://learn.microsoft.com/en-us/azure/azure-arc/data/install-client-tools)
- Provider reqistration
```shell
az provider register --namespace Microsoft.AzureArcData
```

## Create arc data controller in direct connectivity mode
1. Create Azure Arc [data services cluster extension](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/conceptual-extensions)
2. Create a [custom location] on your arc-enabled k8s(https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/conceptual-custom-locations)
3. create the Arc data controller

## Create data services (SQL MI or PostgreSQL)