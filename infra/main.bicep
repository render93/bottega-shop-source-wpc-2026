// Bottega Aurora infrastructure: workload, operations and the SRE Agent's custom role.
// Deploy with scripts/deploy-infra.sh, remove with scripts/destroy-infra.sh.
// rg-aurora-ops (deploy identity, load generator) is shared by all environments and kept between them.
targetScope = 'subscription'

param location string = 'italynorth'

@description('Environment name: the workload and agent resource groups are rg-aurora-prod-<envName> and rg-aurora-agent-<envName>. Use a name never used before to start without metric and alert history.')
@minLength(1)
@maxLength(8)
param envName string

@description('Microsoft Entra admin of the SQL server: the user running the deployment.')
param sqlAdminLogin string

@description('Object ID of the SQL admin user.')
param sqlAdminObjectId string

param tags object = {
  category: 'wpc-2026'
}

var suffix = uniqueString(subscription().id)

resource prodRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-aurora-prod-${envName}'
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
}

output workloadResourceGroup string = prodRg.name
output opsResourceGroup string = opsRg.name
output agentResourceGroup string = 'rg-aurora-agent-${envName}'
output webAppName string = workload.outputs.webAppName
output webAppUrl string = workload.outputs.webAppUrl
output sqlServerName string = workload.outputs.sqlServerName
output sqlServerFqdn string = workload.outputs.sqlServerFqdn
output shopIdentityName string = workload.outputs.shopIdentityName
output shopIdentityClientId string = workload.outputs.shopIdentityClientId
output deployIdentityClientId string = ops.outputs.deployClientId
output loadgenJobName string = ops.outputs.loadgenJobName
output agentRoleDefinitionId string = agentRole.outputs.roleDefinitionId
