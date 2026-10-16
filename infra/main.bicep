// Bottega Aurora infrastructure: workload, operations and the SRE Agent's custom role.
// Deploy with scripts/deploy-infra.sh, remove with scripts/destroy-infra.sh.
targetScope = 'subscription'

param location string = 'italynorth'

@description('Microsoft Entra admin of the SQL server: the user running the deployment.')
param sqlAdminLogin string

@description('Object ID of the SQL admin user.')
param sqlAdminObjectId string

param tags object = {
  category: 'wpc-2026'
}

var suffix = uniqueString(subscription().id)

resource prodRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-aurora-prod'
  location: location
  tags: tags
}

resource opsRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-aurora-ops'
  location: location
  tags: tags
}

module workload 'workload.bicep' = {
  name: 'aurora-workload'
  scope: prodRg
  params: {
    location: location
    suffix: suffix
    sqlAdminLogin: sqlAdminLogin
    sqlAdminObjectId: sqlAdminObjectId
    tags: tags
  }
}

module ops 'ops.bicep' = {
  name: 'aurora-ops'
  scope: opsRg
  params: {
    location: location
    targetUrl: workload.outputs.webAppUrl
    tags: tags
  }
}

module deployRole 'deploy-role.bicep' = {
  name: 'aurora-deploy-role'
  scope: prodRg
  params: {
    webAppName: workload.outputs.webAppName
    principalId: ops.outputs.deployPrincipalId
  }
}

module agentRole 'agent-role.bicep' = {
  name: 'aurora-agent-role'
  params: {
    workloadResourceGroupId: prodRg.id
  }
}

output workloadResourceGroup string = prodRg.name
output opsResourceGroup string = opsRg.name
output webAppName string = workload.outputs.webAppName
output webAppUrl string = workload.outputs.webAppUrl
output sqlServerName string = workload.outputs.sqlServerName
output sqlServerFqdn string = workload.outputs.sqlServerFqdn
output shopIdentityName string = workload.outputs.shopIdentityName
output shopIdentityClientId string = workload.outputs.shopIdentityClientId
output deployIdentityClientId string = ops.outputs.deployClientId
output loadgenJobName string = ops.outputs.loadgenJobName
output agentRoleDefinitionId string = agentRole.outputs.roleDefinitionId
