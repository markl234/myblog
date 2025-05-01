# Terraform configuration for Azure Container Apps, MySQL, and Storage

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "main" {
  name     = "wordpress-rg"
  location = "eastus"
}

resource "azurerm_container_registry" "main" {
  name                = "wordpressacr"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
}

resource "azurerm_mysql_flexible_server" "main" {
  name                = "wordpress-mysql"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  administrator_login = "adminuser"
  administrator_password = "P@ssw0rd123!"
  sku_name            = "B_Standard_B1ms"
  storage_mb          = 5120
  version             = "8.0"
}

resource "azurerm_container_app" "main" {
  name                = "wordpress-container-app"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  container_app_environment_id = azurerm_container_registry.main.id

  template {
    container {
      name   = "wordpress"
      image  = "${azurerm_container_registry.main.login_server}/wordpress:latest"
      cpu    = "0.5"
      memory = "1.0Gi"

      env {
        name  = "WORDPRESS_DB_HOST"
        value = azurerm_mysql_flexible_server.main.fqdn
      }
      env {
        name  = "WORDPRESS_DB_USER"
        value = azurerm_mysql_flexible_server.main.administrator_login
      }
      env {
        name  = "WORDPRESS_DB_PASSWORD"
        value = azurerm_mysql_flexible_server.main.administrator_password
      }
      env {
        name  = "WORDPRESS_DB_NAME"
        value = azurerm_mysql_flexible_server_database.main.name
      }
    }
  }
}