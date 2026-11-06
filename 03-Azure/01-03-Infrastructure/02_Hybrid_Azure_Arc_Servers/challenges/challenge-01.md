# Challenge 1 - Azure Arc prerequisites & onboarding

**[Home](../Readme.md)** - [Next Challenge Solution](challenge-02.md)

## Goal

In challenge 1 you will prepare your Azure environemnt for onboarding of existing Windows- and Linux servers and onboard them to Azure Arc.

## Actions

> **Hackbox Console:** Use your Azure exercise resource group
> <secret group="Lab-Deployment" name="Azure exercise resource group" show="always"></secret>
> for Arc onboarding. The underlying Azure VMs are in the separate simulated on-prem resource group
> <secret group="Lab-Deployment" name="Simulated on-prem resource group" show="always"></secret>.
> The coach supplies the Entra service principal if you lack
> permission to create one; scope its onboarding role to your RG. Resource
> providers are prepared by the shared deployment hook. The two VMs already have
> asynchronous OS preparation requests, but you must verify that preparation
> finished before onboarding. Windows Server 2012 R2 is not provisioned.

- Verify all necessary Azure resources are in place
  - Azure exercise resource group: <secret group="Lab-Deployment" name="Azure exercise resource group" show="always"></secret> (Tag: `SecurityControl=Ignore`)
- Create service principal for onboarding your servers
- Enable required resource providers (if not already enabled)
- Prep existing servers' operating system on-prem
  - Hint: We are using Azure VMs to simulate on-prem servers
- Onboard existing servers to Azure Arc
  - win2012-vm may be skipped unless you plan to do the optional Challenge 6 (Extended Security Updates)

## Success criteria

- You verified your Console-provided Azure exercise resource group with `SecurityControl=Ignore`, or created and tagged your own group when working outside the Console
- You created a service principal with the required role membership, or received a coach-provided one scoped to your resource group
- Successfully prepared existing servers
- Onboarded servers which is visible in the Azure Arc machines blade in the Azure Portal

## Learning resources

- [Plan and deploy Azure Arc-enabled servers](https://learn.microsoft.com/azure/azure-arc/servers/plan-at-scale-deployment)
- [Prerequisites for Connect hybrid machines with Azure Arc-enabled servers](https://learn.microsoft.com/azure/azure-arc/servers/learn/quick-enable-hybrid-vm#prerequisites)
- [Connect hybrid machines with Azure Arc-enabled servers](https://learn.microsoft.com/azure/azure-arc/servers/learn/quick-enable-hybrid-vm#generate-installation-script)
- [Create a service principal for onboarding](https://learn.microsoft.com/azure/azure-arc/servers/onboard-service-principal#create-a-service-principal-for-onboarding-at-scale)
