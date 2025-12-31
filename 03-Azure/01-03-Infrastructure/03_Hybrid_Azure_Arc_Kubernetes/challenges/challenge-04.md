# Challenge 4 - Deploy SQL Managed Instance to your cluster

In this challenge, you'll deploy Azure Arc-enabled data services to your K3s cluster, specifically focusing on SQL Managed Instance. This enables you to run Azure SQL Database services directly on your on-premises Kubernetes cluster while maintaining cloud-connected management, monitoring, and security capabilities.

Azure Arc-enabled data services provide:
* **Cloud-connected database services** running on your own infrastructure
* **Centralized management** through Azure portal, Azure CLI, and Azure Resource Manager
* **Automatic updates and patching** managed through Azure Arc
* **Built-in monitoring and observability** with Log Analytics integration
* **Enterprise-grade security** with Azure Active Directory integration

💡*Hint*: Arc data services require a data controller that acts as the control plane for all data services in the cluster. This controller manages the lifecycle, updates, and monitoring of database instances.

💡*Hint*: Custom locations allow you to use your Arc-enabled Kubernetes cluster as a deployment target for Azure services, creating a seamless hybrid cloud experience.

## Goal
* Deploy Azure Arc data controller to enable data services on your K3s cluster
* Create a SQL Managed Instance running on your on-premises Kubernetes cluster
* Configure monitoring and management capabilities for the data services

## Actions
* Install required Azure CLI extensions for Arc data services (`arcdata`)
* Enable custom locations feature on your Arc-enabled Kubernetes cluster
* Create a custom location that represents your cluster as an Azure deployment target
* Deploy the Azure Arc data controller with appropriate configuration for K3s
* Configure Log Analytics workspace integration for monitoring and telemetry
* Set up authentication credentials for monitoring dashboards (Grafana and Kibana)
* Create a SQL Managed Instance using the data controller
* Verify connectivity and management capabilities

## Success Criteria
* Azure Arc data controller is successfully deployed and running in your cluster (`kubectl get datacontrollers`)
* Custom location is created and visible in Azure portal under Azure Arc > Infrastructure > Custom locations
* Data controller appears in Azure portal under Azure Arc > Data services > Data controllers
* SQL Managed Instance is deployed and shows as "Ready" in both Kubernetes (`kubectl get sqlmi`) and Azure portal
* Monitoring dashboards (Grafana for metrics, Kibana for logs) are accessible and showing data
* You can connect to the SQL Managed Instance using Azure Data Studio or SQL Server Management Studio
* Telemetry and logs are flowing to the configured Log Analytics workspace

## Learning Resources
* [What are Azure Arc-enabled data services?](https://learn.microsoft.com/en-us/azure/azure-arc/data/overview)
* [Create Azure Arc data services cluster extension](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/conceptual-extensions)
* [Create a custom location on your arc-enabled k8s](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/custom-locations#create-custom-location)
* [Create the Arc data controller](https://learn.microsoft.com/en-us/azure/azure-arc/data/create-data-controller-direct-cli)
* [Deploy SQL Managed Instance on Arc-enabled Kubernetes](https://learn.microsoft.com/en-us/azure/azure-arc/data/create-sql-managed-instance)
* [Connect to SQL Managed Instance on Arc](https://learn.microsoft.com/en-us/azure/azure-arc/data/connect-managed-instance)

## Solution - Spoilerwarning
[Solution Steps](../walkthroughs/challenge-04/solution.md)

[Next challenge](challenge-05.md) | [Back](../Readme.md)