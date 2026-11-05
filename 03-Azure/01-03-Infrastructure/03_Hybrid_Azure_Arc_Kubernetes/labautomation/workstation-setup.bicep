param location string = resourceGroup().location
param masterVmName string
param setupScript string
param setupRevision string
param attemptId string
@secure()
param configuration object

resource master 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: masterVmName
}

resource setup 'Microsoft.Compute/virtualMachines/runCommands@2024-07-01' = {
  parent: master
  name: 'workstation-setup'
  location: location
  tags: {
    microhackSetupRevision: setupRevision
  }
  properties: {
    source: {
      script: setupScript
    }
    protectedParameters: [{
      name: 'MICROHACK_CONFIG'
      value: base64(string(configuration))
    }]
    parameters: [{
      name: 'MICROHACK_ATTEMPT_ID'
      value: attemptId
    }]
    asyncExecution: false
    timeoutInSeconds: 3600
    treatFailureAsDeploymentFailure: true
  }
}
