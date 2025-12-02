![image](img/banner.png)

# MicroHack Azure Arc-enabled Kubernetes

- [**MicroHack Introduction**](#microhack-introduction)
  - [What is Azure Arc for Kubernetes?](#what-is-azure-arc-for-kubernetes)
- [**MicroHack Context**](#microhack-context)
- [**Objectives**](#objectives)
- [**MicroHack Challenges**](#microhack-challenges)
  - [General Prerequisites](#general-prerequisites)
  - [Challenge 1 - Onboarding your Kubernetes Cluster](#challenge-1---onboarding-your-kubernetes-cluster)


## MicroHack Introduction

### What is Azure Arc for Kubernetes?

Azure Arc-enabled Kubernetes allows you to attach Kubernetes clusters running anywhere so that you can manage and configure them in Azure. By managing all of your Kubernetes resources in a single control plane, you can enable a more consistent development and operation experience, helping you run cloud-native apps anywhere and on any Kubernetes platform.

![image](./img/architectural-overview.png)

Once your Kubernetes clusters are connected to Azure, you can:

- View all connected Kubernetes clusters for inventory, grouping, and tagging, along with your Azure Kubernetes Service (AKS) clusters.

- Configure clusters and deploy applications using GitOps-based configuration management.

- View and monitor your clusters using Azure Monitor for containers.

- Enforce threat protection using Microsoft Defender for Kubernetes.

- Ensure governance through applying policies with Azure Policy for Kubernetes.

- Grant access and connect to your Kubernetes clusters from anywhere, and manage access by using Azure role-based access control (RBAC) on your cluster.

- Deploy machine learning workloads using Azure Machine Learning for Kubernetes clusters.

- Deploy and manage Kubernetes applications from Azure Marketplace.

- Deploy Azure PaaS services that allow you to take advantage of specific hardware, comply with data residency requirements, or enable new scenarios. Examples of services include:

    - Azure Arc-enabled data services
    - Azure Machine Learning for Kubernetes clusters
    - Workload Orchestration
    - Event Grid on Kubernetes
    - App Services on Azure Arc
    - Open Service Mesh

## MicroHack Context

This MicroHack is a challenge-based experience which will walk you through the onboarding process and step by step enabling additional use cases.

💡 *Optional*: Have a look at the following resources after completing this lab to deepen your learning:

* [Azure Arc-enabled Kubernetes documentation](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/)
* [Azure Arc Jumpstart - Arc-enabled Kubernetes](https://jumpstart.azure.com/azure_arc_jumpstart/azure_arc_k8s)
* [Azure Arc Jumpstart - Data Services](https://jumpstart.azure.com/azure_arc_jumpstart/azure_arc_data)
* [Azure Arc - Workload Orchestration](https://learn.microsoft.com/en-us/azure/azure-arc/workload-orchestration/overview)
* [Azure Arc Jumpstart - Machine Learning](https://jumpstart.azure.com/azure_arc_jumpstart/azure_arc_ml)
* [Azure Arc Jumpstart - Iot Operations](https://jumpstart.azure.com/azure_arc_jumpstart/azure_edge_iot_ops)
* [Speed Innovation with Arc-enabled Kubernetes Applications](https://techcommunity.microsoft.com/blog/azurearcblog/speed-innovation-with-arc-enabled-kubernetes-applications/4298658)
* [Azure Arc-Enabled Kubernetes now available on Azure Marketplace](https://techcommunity.microsoft.com/blog/azurearcblog/azure-arc-enabled-kubernetes-now-available-on-azure-marketplace/4034060)
* [Introduction to Azure Arc landing zone accelerator for hybrid and multicloud](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/scenarios/hybrid/enterprise-scale-landing-zone)

## Objectives

After completing this MicroHack you will be familiar with:

* How to connect your Kubernetes cluster running anywhere to Azure Arc
* Understand how you can streamline your operations and development processes for your Kubernetes clusters running anywhere
* Deploying Azure PaaS services such as SQL Managed Instance in your Kubernetes cluster running anywhere 

## MicroHack Challenges

### General Prerequisites

In order to successfully work through the challenges in this MicroHack, you will need the following prerequisites:

* [An Azure account with an active subscription](https://azure.microsoft.com/free/?WT.mc_id=A261C142F)
* [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (Hint: Make sure to use the lastest version)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-using-native-package-management)
* [Helm] (https://helm.sh/docs/intro/install/)

💡*Hint*: The solution has been verified using [Visual Studio Code](https://code.visualstudio.com/) with integrated Linux Bash Shell ([WSL(https://learn.microsoft.com/en-us/windows/wsl/install)]). In order to clone this repository to your local system, use either git or the github plugin for VSC.

## Challenge 1 - Onboarding your Kubernetes Cluster


### Goal
In challenge 1 you will connect/onboard your existing K8s cluster to Azure Arc. 

### Actions
* Verify all prerequisites are in place
  * Resource Providers
  * Azure CLI extensions
  * Resource group (Name: mh-arc-k8s)
  * Connectivity to required Azure endpoints
* Deploy the Azure Arc agent pods to your k8s cluster
* Assign permissions to view k8s resources in the Azure portal

### Success Criteria
* Your k8s cluster appears in the Azure portal under Azure Arc > Infrastructure > Kubernetes clusters and is in status "Connected"
* In the Azure portal below Kubernetes resources > Workloads you can see all deployments and pods running on your cluster.

### Learning Resources
* (https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/azure-rbac)
* (https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/kubernetes-resource-view)

### Solution - Spoilerwarning
[Solution Steps](walkthrough/01-connect/solution.md)

## Challenge 2 - Configure Gitops for cluster management

### Goal

### Actions

### Success Criteria

### Learning Resources

### Solution - Spoilerwarning

## Challenge 3 - Enable Azure Monitor for Containers

### Goal

### Actions

### Success Criteria

### Learning Resources

### Solution - Spoilerwarning

## Challenge 4 - Deploy SQL Managed Instance to your cluster

### Goal

### Actions

### Success Criteria

### Learning Resources

### Solution - Spoilerwarning

## Challenge 5 - Improve Governance using Azure Policy for Kubernetes

### Goal

### Actions

### Success Criteria

### Learning Resources

### Solution - Spoilerwarning

## Challenge 6 - Ship Azure Machine Learning Container to your cluster

### Goal

### Actions

### Success Criteria

### Learning Resources

### Solution - Spoilerwarning

## Contributors
* Simon Schwingel [GitHub](https://github.com/skiddder); [LinkedIn](https://www.linkedin.com/in/simon-schwingel-b602869a/)