// Bicep file for Azure Container Apps, MySQL, and Storage
param location string = resourceGroup().location
param containerAppName string = 'wordpress-container-app'
param mysqlServerName string = 'wordpress-mysql-server'
param mysqlDatabaseName string = 'wordpressdb'
param mysqlAdminUsername string = 'adminuser'
param mysqlAdminPassword string = 'P@ssw0rd123!'

resource containerApp 'Microsoft.App/containerApps@2023-03-01' = {
  name: containerAppName
  location: location
  properties: {
    managedEnvironmentId: resourceId('Microsoft.App/managedEnvironments', 'default')
    configuration: {
      ingress: {
        external: true
        targetPort: 80
      }
      secrets: [
        {
          name: 'mysql-password'
          value: mysqlAdminPassword
        }
      ]
      registries: []
    }
    template: {
      containers: [
        {
          name: 'wordpress'
          image: 'your-container-registry.azurecr.io/wordpress:latest'
          env: [
            {
              name: 'WORDPRESS_DB_HOST'
              value: mysqlServerName
            }
            {
              name: 'WORDPRESS_DB_USER'
              value: mysqlAdminUsername
            }
            {
              name: 'WORDPRESS_DB_PASSWORD'
              value: mysqlAdminPassword
            }
            {
              name: 'WORDPRESS_DB_NAME'
              value: mysqlDatabaseName
            }
          ]
        }
      ]
    }
  }
}

resource mysqlServer 'Microsoft.DBforMySQL/flexibleServers@2023-03-01' = {
  name: mysqlServerName
  location: location
  properties: {
    administratorLogin: mysqlAdminUsername
    administratorLoginPassword: mysqlAdminPassword
    version: '8.0'
    storage: {
      storageSizeGB: 32
    }
  }
}

resource mysqlDatabase 'Microsoft.DBforMySQL/flexibleServers/databases@2023-03-01' = {
  name: mysqlDatabaseName
  parent: mysqlServer
}