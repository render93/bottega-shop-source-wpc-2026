// Operations: the CD pipeline identity and the k6 load generator on Container Apps.
param location string

@description('Shop URL the load generator calls.')
param targetUrl string

param tags object

// Federated credentials are added per repository copy by the stage preparation, not here.
resource deployId 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-aurora-deploy'
  location: location
  tags: tags
}

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-aurora-loadgen'
  location: location
  tags: tags
  properties: {
    workloadProfiles: [
      { name: 'Consumption', workloadProfileType: 'Consumption' }
    ]
  }
}

// Manual job: start it with `az containerapp job start`. The shop gets traffic from Azure, not from a laptop.
resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: 'job-aurora-loadgen'
  location: location
  tags: tags
  properties: {
    environmentId: env.id
    workloadProfileName: 'Consumption'
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 10000
      replicaRetryLimit: 0
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
      }
    }
    template: {
      containers: [
        {
          name: 'k6'
          image: 'grafana/k6:0.54.0'
          command: [ 'sh', '-c', 'printf "%s" "$K6_SCRIPT" > /tmp/checkout.js && k6 run /tmp/checkout.js' ]
          env: [
            { name: 'K6_SCRIPT', value: loadTextContent('../loadgen/checkout.js') }
            { name: 'TARGET_URL', value: targetUrl }
            { name: 'RATE', value: '12' }
            { name: 'TIME_UNIT', value: '1m' }
            { name: 'DURATION', value: '150m' }
            { name: 'PROMO_SHARE', value: '0.08' }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
    }
  }
}

output deployClientId string = deployId.properties.clientId
output deployPrincipalId string = deployId.properties.principalId
output loadgenJobName string = job.name
