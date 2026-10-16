// Shop workload: Web App with a staging slot, Azure SQL, telemetry and the 5xx alert.
param location string
param suffix string
param sqlAdminLogin string
param sqlAdminObjectId string
param tags object

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-aurora-${suffix}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-aurora-${suffix}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: law.id
  }
}

// One identity for both slots: the code moves between slots on swap, the identity does not.
resource shopId 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-aurora-shop'
  location: location
  tags: tags
}

resource sql 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: 'sql-aurora-${suffix}'
  location: location
  tags: tags
  properties: {
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: sqlAdminLogin
      sid: sqlAdminObjectId
      principalType: 'User'
      tenantId: tenant().tenantId
    }
  }
}

// 0.0.0.0 = "Allow Azure services": the Web App reaches SQL without VNet integration.
resource sqlAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sql
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Fixed tier, no serverless: auto-pause would freeze the live counter.
resource db 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sql
  name: 'aurora'
  location: location
  tags: tags
  sku: { name: 'S0', tier: 'Standard' }
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'asp-aurora-${suffix}'
  location: location
  tags: tags
  kind: 'linux'
  sku: { name: 'P0v3', capacity: 1 }
  properties: { reserved: true }
}

var siteConfig = {
  linuxFxVersion: 'DOTNETCORE|10.0'
  alwaysOn: true
  ftpsState: 'Disabled'
  minTlsVersion: '1.2'
}

var appSettings = {
  APPLICATIONINSIGHTS_CONNECTION_STRING: appInsights.properties.ConnectionString
  PAYMENT_TIMEOUT_MS: '3000'
}

var connectionStrings = {
  Shop: {
    type: 'SQLAzure'
    value: 'Server=tcp:${sql.properties.fullyQualifiedDomainName},1433;Database=${db.name};Authentication=Active Directory Managed Identity;User Id=${shopId.properties.clientId};Encrypt=True;Connect Timeout=5;'
  }
}

resource web 'Microsoft.Web/sites@2024-04-01' = {
  name: 'bottega-aurora-${suffix}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${shopId.id}': {} }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: siteConfig
  }
}

resource webSettings 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: web
  name: 'appsettings'
  properties: appSettings
}

resource webConnections 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: web
  name: 'connectionstrings'
  properties: connectionStrings
}

// PAYMENT_TIMEOUT_MS stays with the slot instead of following the code on swap.
resource stickySettings 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: web
  name: 'slotConfigNames'
  properties: {
    appSettingNames: [ 'PAYMENT_TIMEOUT_MS' ]
  }
}

resource staging 'Microsoft.Web/sites/slots@2024-04-01' = {
  parent: web
  name: 'staging'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${shopId.id}': {} }
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: siteConfig
  }
}

resource stagingSettings 'Microsoft.Web/sites/slots/config@2024-04-01' = {
  parent: staging
  name: 'appsettings'
  properties: appSettings
}

resource stagingConnections 'Microsoft.Web/sites/slots/config@2024-04-01' = {
  parent: staging
  name: 'connectionstrings'
  properties: connectionStrings
}

// The SRE Agent response plan filters on this exact name: keep it fixed.
// The site-level Http5xx metric covers the production slot only.
resource checkout5xx 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-checkout-5xx'
  location: 'global'
  tags: tags
  properties: {
    description: 'Errori 5xx sul negozio Bottega Aurora (slot production)'
    severity: 1
    enabled: true
    scopes: [ web.id ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT1M'
    autoMitigate: true
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'http5xx'
          metricNamespace: 'Microsoft.Web/sites'
          metricName: 'Http5xx'
          timeAggregation: 'Total'
          operator: 'GreaterThan'
          threshold: 3
        }
      ]
    }
  }
}

output webAppName string = web.name
output webAppUrl string = 'https://${web.properties.defaultHostName}'
output sqlServerName string = sql.name
output sqlServerFqdn string = sql.properties.fullyQualifiedDomainName
output shopIdentityName string = shopId.name
output shopIdentityClientId string = shopId.properties.clientId
