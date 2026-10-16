// The CD pipeline deploys to the staging slot and swaps: Website Contributor on the Web App only.
param webAppName string
param principalId string

var websiteContributor = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'de139f84-1756-47ae-9be6-808fbbe84772')

resource web 'Microsoft.Web/sites@2024-04-01' existing = {
  name: webAppName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(web.id, principalId, websiteContributor)
  scope: web
  properties: {
    roleDefinitionId: websiteContributor
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: 'CD pipeline: deploy to staging and swap'
  }
}
