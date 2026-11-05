param location string = resourceGroup().location
param labPrefix string
@minLength(1)
@maxLength(64)
param workstationName string
@minValue(1)
@maxValue(199)
param networkIndex int
param hubVnetId string
param adminUsername string = 'mhadmin'
@secure()
param adminPassword string
@secure()
param masterSetupScript string
@secure()
param workerSetupScript string
param winrmCommand string
param vmSize string = 'Standard_D4ds_v6'

var nodeNames = ['master', 'worker1', 'worker2']
var nodeIps = [10, 11, 12]
var nodeVmNames = [for node in nodeNames: '${labPrefix}-k8s-${node}']
var vmNames = concat(nodeVmNames, [workstationName])
var tags = {
  microhack: 'arc-kubernetes'
}

resource outboundIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${labPrefix}-outbound-ip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nat 'Microsoft.Network/natGateways@2024-05-01' = {
  name: '${labPrefix}-nat'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [{ id: outboundIp.id }]
    idleTimeoutInMinutes: 10
  }
}

resource nodeNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${labPrefix}-nodes-nsg'
  location: location
  properties: {
    securityRules: [{
      name: 'ManagementAndCluster'
      properties: {
        priority: 1000
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourcePortRange: '*'
        destinationPortRanges: ['22', '6443', '10250', '30000-32767']
        sourceAddressPrefix: 'VirtualNetwork'
        destinationAddressPrefix: '*'
      }
    }, {
      name: 'Flannel'
      properties: {
        priority: 1001
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Udp'
        sourcePortRange: '*'
        destinationPortRange: '8472'
        sourceAddressPrefix: '10.${networkIndex}.1.0/24'
        destinationAddressPrefix: '*'
      }
    }, {
      name: 'DenyOtherInbound'
      properties: {
        priority: 4096
        direction: 'Inbound'
        access: 'Deny'
        protocol: '*'
        sourcePortRange: '*'
        destinationPortRange: '*'
        sourceAddressPrefix: '*'
        destinationAddressPrefix: '*'
      }
    }]
  }
}

resource workstationNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${workstationName}-nsg'
  location: location
  properties: {
    securityRules: [{
      name: 'BastionRdp'
      properties: {
        priority: 1000
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourcePortRange: '*'
        destinationPortRange: '3389'
        sourceAddressPrefix: '10.200.0.0/24'
        destinationAddressPrefix: '*'
      }
    }, {
      name: 'AnsibleFromMaster'
      properties: {
        priority: 1001
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        sourcePortRange: '*'
        destinationPortRange: '5986'
        sourceAddressPrefix: '10.${networkIndex}.1.10'
        destinationAddressPrefix: '*'
      }
    }, {
      name: 'DenyOtherInbound'
      properties: {
        priority: 4096
        direction: 'Inbound'
        access: 'Deny'
        protocol: '*'
        sourcePortRange: '*'
        destinationPortRange: '*'
        sourceAddressPrefix: '*'
        destinationAddressPrefix: '*'
      }
    }]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${labPrefix}-k8s-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.${networkIndex}.0.0/16']
    }
    subnets: [for subnet in [
      {
        name: 'k3s'
        cidr: '1'
        nsg: nodeNsg.id
      }
      {
        name: 'workstation'
        cidr: '2'
        nsg: workstationNsg.id
      }
    ]: {
      name: subnet.name
      properties: {
        addressPrefix: '10.${networkIndex}.${subnet.cidr}.0/24'
        defaultOutboundAccess: false
        natGateway: {
          id: nat.id
        }
        networkSecurityGroup: {
          id: subnet.nsg
        }
      }
    }]
  }
}

resource spokePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: vnet
  name: 'to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource nodeNics 'Microsoft.Network/networkInterfaces@2024-05-01' = [for (node, i) in nodeNames: {
  name: '${labPrefix}-k8s-${node}-nic'
  location: location
  properties: {
    ipConfigurations: [{
      name: 'internal'
      properties: {
        privateIPAllocationMethod: 'Static'
        privateIPAddress: '10.${networkIndex}.1.${nodeIps[i]}'
        subnet: {
          id: '${vnet.id}/subnets/k3s'
        }
      }
    }]
  }
}]

resource nodes 'Microsoft.Compute/virtualMachines@2024-07-01' = [for (node, i) in nodeNames: {
  name: '${labPrefix}-k8s-${node}'
  location: location
  tags: union(tags, { Role: node })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    osProfile: {
      computerName: '${labPrefix}-k8s-${node}'
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nodeNics[i].id }]
    }
  }
}]

resource workstationNic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${workstationName}-nic'
  location: location
  properties: {
    ipConfigurations: [{
      name: 'internal'
      properties: {
        privateIPAllocationMethod: 'Static'
        privateIPAddress: '10.${networkIndex}.2.10'
        subnet: {
          id: '${vnet.id}/subnets/workstation'
        }
      }
    }]
  }
}

resource workstation 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: workstationName
  location: location
  tags: union(tags, { Role: 'workstation' })
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer: 'windows-11'
        sku: 'win11-24h2-pro'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    osProfile: {
      computerName: 'mhworkstation'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    networkProfile: {
      networkInterfaces: [{ id: workstationNic.id }]
    }
  }
}

resource masterSetup 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: nodes[0]
  name: 'k3s-setup'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      script: masterSetupScript
    }
  }
}

resource workerSetup 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = [for i in range(1, 2): {
  parent: nodes[i]
  name: 'k3s-setup'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      script: workerSetupScript
    }
  }
  dependsOn: [masterSetup]
}]

resource winrm 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: workstation
  name: 'enable-winrm'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      commandToExecute: winrmCommand
    }
  }
}

resource shutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = [for vmName in vmNames: {
  name: 'shutdown-computevm-${vmName}'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: '1800'
    }
    timeZoneId: 'W. Europe Standard Time'
    targetResourceId: resourceId('Microsoft.Compute/virtualMachines', vmName)
    notificationSettings: {
      status: 'Disabled'
    }
  }
  dependsOn: [nodes, workstation]
}]

output spokeVnetId string = vnet.id
output masterIp string = '10.${networkIndex}.1.10'
output workstationId string = workstation.id
