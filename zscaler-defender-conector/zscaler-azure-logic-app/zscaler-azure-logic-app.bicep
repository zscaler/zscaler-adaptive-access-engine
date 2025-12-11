@description('The base name for all resources. Should be unique.')
@minLength(3)
param baseName string = 'zaa-001'

@description('The location for the resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('The location for the Logic App and API Connections. Should be a location where the connectors are available.')
param logicAppLocation string = location

@description('The interval for the Logic App trigger. Defaults to 15.')
param logicAppTriggerInterval int = 15

@description('The frequency for the Logic App trigger. Defaults to \'Minute\'.')
@allowed([
  'Minute'
  'Hour'
  'Day'
])
param logicAppTriggerFrequency string = 'Minute'

@secure()
@description('The Client ID for the Defender Tenant.')
param defenderClientId string

@secure()
@description('The Client Secret for the Defender Tenant.')
param defenderClientSecret string

@description('The Tenant ID of the Defender Tenant.')
param defenderTenantId string

@description('Optional. An array of public IP addresses or CIDR ranges to allow access to the Event Hub namespace.')
param allowedIpAddresses array = [
  '54.81.126.159'
  '34.232.89.148'
  '44.221.241.232'
  '44.238.108.254'
  '52.32.35.254'
  '35.162.38.214'
  '3.77.196.85'
  '3.123.144.88'
  '3.124.174.255'
  '13.36.73.15'
  '15.236.162.60'
  '15.236.246.90'
]

@description('Optional. The resource ID of a virtual network subnet to allow access to the Event Hub namespace. A service endpoint for Microsoft.EventHub must be enabled on this subnet.')
param allowedVnetSubnetId string = ''

var keyVaultName = '${baseName}-kv'
var eventHubNamespaceName = '${baseName}-ns'
var logicAppName = '${baseName}-logicapp'
var eventHubName = '${baseName}-evh'
var eventHubConnectionName = 'eventhubs'
var keyVaultConnectionName = 'keyvault'

// Built-in Role Definition IDs
var keyVaultSecretsUserRoleDefinitionId = '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
var eventHubDataSenderRoleDefinitionId = '2b629674-e913-4c01-ae53-ef4638d8f975'  // Azure Event Hubs Data Sender

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-05-01-preview' = {
  name: eventHubNamespaceName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: true
    isAutoInflateEnabled: true
    maximumThroughputUnits: 4
    kafkaEnabled: true
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId

    accessPolicies: []
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enabledForTemplateDeployment: true
    enablePurgeProtection: true
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
  }
}

resource eventHubConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: eventHubConnectionName
  location: logicAppLocation
    properties: {
    displayName: eventHubConnectionName
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', logicAppLocation, eventHubConnectionName)
      type: 'Microsoft.Web/locations/managedApis'
    }
    parameterValueSet: {
      name: 'managedIdentityAuth'
      values: { 
        namespaceEndpoint: {
          value: 'sb://${eventHubNamespace.name}.servicebus.windows.net/'
        }
      }
    }
  }
}

resource keyVaultConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: keyVaultConnectionName
  location: logicAppLocation
  properties: {
    displayName: keyVaultConnectionName
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', logicAppLocation, keyVaultConnectionName)
      type: 'Microsoft.Web/locations/managedApis'
    }
    parameterValueType: 'Alternative'
    alternativeParameterValues: {
      vaultName: keyVault.name
    }
  }
}

resource eventHubNamespaceRootKey 'Microsoft.EventHub/namespaces/authorizationrules@2024-05-01-preview' = {
  parent: eventHubNamespace
  name: 'RootManageSharedAccessKey'
  properties: {
    rights: [
      'Listen'
      'Manage'
      'Send'
    ]
  }
}

resource eventHubNamespaceSasPolicy 'Microsoft.EventHub/namespaces/authorizationrules@2024-05-01-preview' = {
  parent: eventHubNamespace
  name: 'zs-aae-sas-policy'
  properties: {
    rights: [
      'Listen'
    ]
  }
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-05-01-preview' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    retentionDescription: {
      cleanupPolicy: 'Delete'
      retentionTimeInHours: 2
    }
    partitionCount: 1
    status: 'Active'
  }
}

resource eventHubNetworkRuleSet 'Microsoft.EventHub/namespaces/networkrulesets@2024-05-01-preview' = {
  parent: eventHubNamespace
  name: 'default'
  properties: {
    publicNetworkAccess: 'Enabled' // Keep enabled to allow trusted service access and IP/VNet rules.
    defaultAction: 'Deny' // Secure by default: Deny traffic.
    virtualNetworkRules: !empty(allowedVnetSubnetId) ? [
      {
        subnet: {
          id: allowedVnetSubnetId
        }
        ignoreMissingVnetServiceEndpoint: false
      }
    ] : []
    ipRules: [for ipAddress in allowedIpAddresses: {
      ipMask: ipAddress
      action: 'Allow'
    }]
    trustedServiceAccessEnabled: true // Allow trusted services like Logic Apps.
  }
}

resource defenderClientIdSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'DEFENDER-CLIENT-ID'
  properties: {
    value: defenderClientId
    attributes: {
      enabled: true
    }
  }
}

resource defenderClientSecretSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'DEFENDER-CLIENT-SECRET'
  properties: {
    value: defenderClientSecret
    attributes: {
      enabled: true
    }
  }
}

resource eventHubAuthRule 'Microsoft.EventHub/namespaces/eventhubs/authorizationrules@2024-05-01-preview' = {
  parent: eventHub
  name: 'zs-aae-listen-policy'
  properties: {
    rights: [
      'Listen'
    ]
  }
}

resource eventHubConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-05-01-preview' = {
  parent: eventHub
  name: '$Default'
  properties: {}
}

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: logicAppLocation
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        'DEFENDER-BASE-URL': {
          defaultValue: 'https://login.microsoftonline.com/${defenderTenantId}'
          type: 'String'
        }
        'SCOPE-API': {
          defaultValue: 'https://api.securitycenter.microsoft.com/.default'
          type: 'String'
        }
        'MACHINES-API-ENDPOINT': {
          defaultValue: 'https://api.security.microsoft.com/api/machines'
          type: 'String'
        }
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
        'logicAppTriggerInterval': {
          type: 'Int'
          defaultValue: 15
        }
        'logicAppTriggerFrequency': {
          type: 'String'
          defaultValue: 'Minute'
        }
      }
      triggers: {
        Recurrence: {
          recurrence: {
            interval: '@parameters(\'logicAppTriggerInterval\')'
            frequency: '@parameters(\'logicAppTriggerFrequency\')'
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Get_Client_Id: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'keyvault\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/secrets/@{encodeURIComponent(\'DEFENDER-CLIENT-ID\')}/value'
          }
        }
        Get_Client_Secret: {
          runAfter: {
            Get_Client_Id: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'keyvault\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/secrets/@{encodeURIComponent(\'DEFENDER-CLIENT-SECRET\')}/value'
          }
        }
        Get_Oauth_Token: {
          runAfter: {
            Get_Client_Secret: [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            uri: '@{parameters(\'DEFENDER-BASE-URL\')}/oauth2/v2.0/token'
            method: 'POST'
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded'
            }
            body: 'grant_type=client_credentials&\nclient_id=@{body(\'Get_Client_Id\')?[\'value\']}&\nclient_secret=@{body(\'Get_Client_Secret\')?[\'value\']}&\nscope=@{parameters(\'SCOPE-API\')}'
            retryPolicy: {
              type: 'fixed'
              count: 3
              interval: 'PT30S'
            }
          }
        }
        Get_Machines: {
          runAfter: {
            Get_Oauth_Token: [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            uri: '@parameters(\'MACHINES-API-ENDPOINT\')'
            method: 'GET'
            headers: {
              Authorization: 'Bearer @{body(\'Get_Oauth_Token\')?[\'access_token\']}'
            }
            retryPolicy: {
              type: 'fixed'
              count: 3
              interval: 'PT30S'
            }
          }
        }
        Send_event: {
          runAfter: {
            Get_Machines: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'eventhubs\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              ContentData: '@base64(string(body(\'Get_Machines\')))'
            }
            path: '/@{encodeURIComponent(\'${eventHubName}\')}/events'
          }
        }
      }
      outputs: {}
    }
    parameters: {
      logicAppTriggerInterval: {
        value: logicAppTriggerInterval
      }
      logicAppTriggerFrequency: {
        value: logicAppTriggerFrequency
      }
      '$connections': {
        value: {
          keyvault: {
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', logicAppLocation, 'keyvault')
            connectionId: keyVaultConnection.id
            connectionName: 'keyvault'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
          eventhubs: {
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', logicAppLocation, 'eventhubs')
            connectionId: eventHubConnection.id
            connectionName: 'eventhubs'
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
        }
      }
    }
  }
}

// Grant Logic App's Managed Identity access to Key Vault secrets
resource logicAppKvRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, logicApp.id, keyVaultSecretsUserRoleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleDefinitionId)
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Logic App's Managed Identity access to send events to Event Hub
resource logicAppEhRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: eventHubNamespace
  name: guid(eventHubNamespace.id, logicApp.id, eventHubDataSenderRoleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', eventHubDataSenderRoleDefinitionId)
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
