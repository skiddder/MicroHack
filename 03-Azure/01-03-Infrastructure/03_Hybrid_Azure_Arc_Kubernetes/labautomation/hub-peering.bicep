param spokeVnetId string
param labPrefix string

resource hub 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: 'mh-k8s-hub'
}

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: hub
  name: 'to-${labPrefix}'
  properties: {
    remoteVirtualNetwork: {
      id: spokeVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}
