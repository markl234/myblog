# Terraform configuration for Azure Container Apps, MySQL, and Storage

variable "subscription_id" {
  description = "The Azure subscription ID"
  type        = string
}

variable "client_id" {
  description = "The Azure client ID"
  type        = string
}

variable "client_secret" {
  description = "The Azure client secret"
  type        = string
}

variable "tenant_id" {
  description = "The Azure tenant ID"
  type        = string
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
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
  version             = "8.0.21"
}

resource "azurerm_container_app" "main" {
  name                = "wordpress-container-app"
  resource_group_name = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_registry.main.id
  revision_mode       = "Single"

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
        value = "wordpressdb"
      }
    }
  }
}