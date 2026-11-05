param location string = resourceGroup().location
param participantIds array

var readerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')

resource hub 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'mh-k8s-hub'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.200.0.0/16']
    }
    subnets: [{
      name: 'AzureBastionSubnet'
      properties: {
        addressPrefix: '10.200.0.0/24'
      }
    }]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'mh-k8s-bastion-ip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: 'mh-k8s-bastion'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    enableTunneling: true
    enableIpConnect: true
    ipConfigurations: [{
      name: 'bastion'
      properties: {
        subnet: {
          id: '${hub.id}/subnets/AzureBastionSubnet'
        }
        publicIPAddress: {
          id: publicIp.id
        }
      }
    }]
  }
}

resource readers 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for userId in participantIds: {
  name: guid(resourceGroup().id, userId, readerRoleId)
  properties: {
    principalId: userId
    principalType: 'User'
    roleDefinitionId: readerRoleId
  }
}]

output bastionName string = bastion.name
output hubVnetId string = hub.id
