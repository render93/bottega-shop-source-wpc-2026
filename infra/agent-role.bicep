// Least-privilege role for the Azure SRE Agent: read the Web App and its settings, swap slots,
// nothing else (no config/write). The agent setup assigns it on each agent creation.
// Role definitions cannot carry tags: delete it by name ("Aurora Agent Swap Operator") when no longer needed.
targetScope = 'subscription'

param workloadResourceGroupId string

var roleName = 'Aurora Agent Swap Operator'

resource swapOperator 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, roleName)
  properties: {
    roleName: roleName
    description: 'Bottega Aurora demo: lets the Azure SRE Agent read the Web App and swap deployment slots, but not change configuration.'
    type: 'CustomRole'
    assignableScopes: [ workloadResourceGroupId ]
    permissions: [
      {
        actions: [
          'Microsoft.Web/sites/read'
          'Microsoft.Web/sites/slots/read'
          'Microsoft.Web/sites/config/read'
          'Microsoft.Web/sites/slots/config/read'
          'Microsoft.Web/sites/config/list/action'
          'Microsoft.Web/sites/slots/config/list/action'
          'Microsoft.Web/sites/slotsdiffs/action'
          'Microsoft.Web/sites/slots/slotsdiffs/action'
          'Microsoft.Web/sites/slotsswap/action'
          'Microsoft.Web/sites/slots/slotsswap/action'
        ]
        notActions: []
      }
    ]
  }
}

output roleDefinitionId string = swapOperator.id
